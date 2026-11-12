import Foundation
import SwiftUI
import ServiceManagement
import UserNotifications
import BatteryCore

/// State + actions for every view. One poll loop; the daemon is the source of truth for everything in `status`.
/// The app keeps no copy of a setting: a control shows the daemon's value, or the value it just asked for until the
/// daemon has answered (`Knob`).
@MainActor
@Observable
final class AppModel {

	enum Helper: Equatable { case unknown, ready, notRegistered, needsApproval, unreachable }

	/// Last snapshot. Kept while the helper is silent (views gate on `helper`), so the menu bar keeps its percent
	/// and a limit that holds charging off is still known to.
	private( set ) var status: BatteryStatus?
	private( set ) var helper: Helper = .unknown
	/// A failed action or repair. Sticky until dismissed or the next action succeeds.
	private( set ) var error: String?
	/// The setup window opens on its own once per launch, the first time the helper needs setting up or approving
	var setupPrompted = false
	var needsSetup: Bool { helper == .notRegistered || helper == .needsApproval }
	/// A limit that holds charging off keeps doing so with no helper to lift it
	var limitWasActive: Bool { status?.maintain != nil }

	/// Actions in flight. Polling pauses while > 0 so an old snapshot can't overwrite a fresh change.
	private var inFlight = 0
	var busy: Bool { inFlight > 0 }

	private( set ) var legacyLeftovers: [ String ] = []

	/// Launch at login for the menu bar app itself
	var launchAtLogin: Bool {
		get { loginItem }
		set { setLaunchAtLogin( newValue ) }
	}
	private var loginItem = SMAppService.mainApp.status == .enabled

	private let client = DaemonClient()
	private let daemon = SMAppService.daemon( plistName: "co.palokaj.battery.daemon.plist" )
	private let defaults = UserDefaults.standard
	private var poll: Task<Void, Never>?
	private var alertedLow = false
	private var restartedHelper = false
	/// Auto-repair of a registered helper that stopped answering: after two silent polls in a row, at most every 10 minutes
	private var lastHeal: Date?
	private var silentPolls = 0
	private var actionTail: Task<Void, Never>?

	init() {
		UserDefaults.registerBatteryDefaults()
		enableLoginItemOnce()
		startPolling()
	}

	// MARK: Polling

	func startPolling() {
		poll?.cancel()
		poll = Task { [ weak self ] in
			while !Task.isCancelled {
				await self?.refresh()
				try? await Task.sleep( for: .seconds( 5 ) )
			}
		}
	}

	func refresh() async {
		loginItem = SMAppService.mainApp.status == .enabled
		guard inFlight == 0 else { return }

		do {
			let fresh = try await client.snapshot()
			guard inFlight == 0 else { return }     // an action started while we waited: this snapshot is already stale
			status = fresh
			silentPolls = 0
			helper = .ready
			restartOutdatedHelper( fresh.daemonVersion )
			checkLowBattery()
			if legacyLeftovers.isEmpty, !defaults.bool( forKey: Pref.legacyDeclined ) { legacyLeftovers = ( try? await client.legacyFound() ) ?? [] }
		} catch {
			// Not answering: find out why
			switch daemon.status {
			case .notRegistered, .notFound: helper = .notRegistered
			case .requiresApproval: helper = .needsApproval
			default: helper = .unreachable; healUnreachableHelper()
			}
		}
	}

	// MARK: Helper lifecycle

	/// The setup button: whatever the current state needs
	func setUpHelper() {
		switch helper {
		case .unreachable: repairHelper()
		case .needsApproval: openLoginItems()
		default: registerHelper()
		}
	}

	func registerHelper() {
		do { try daemon.register() } catch { self.error = error.localizedDescription }
		if daemon.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
		Task { await refresh() }
	}

	/// Registered but not answering (app was moved, bundle replaced, stale job spec): start over.
	/// Observed on macOS 26: when the helper is already approved, one unregister + register refreshes the job;
	/// if it still doesn't answer, a second round does. Approval itself is only asked when it was switched off.
	/// A job removed from launchd behind our back (`launchctl bootout`) comes back with unregister + register (2026-11-12, macOS 26.1);
	/// if it ever doesn't, switching the Login Items toggle off and on does, so we send the user there as a last resort.
	/// Through `perform`: serialized with every other action, so a heal and a click can't unregister under each other.
	func repairHelper() {
		guard !busy else { return }
		perform { [ self ] in
			var answering = false
			for _ in 0..<2 {
				try? await daemon.unregister()
				try? await Task.sleep( for: .seconds( 1 ) )
				try daemon.register()
				if daemon.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems(); break }

				try? await Task.sleep( for: .seconds( 4 ) )
				answering = ( try? await client.snapshot() ) != nil
				if answering { break }
			}
			if !answering, daemon.status == .enabled {
				SMAppService.openSystemSettingsLoginItems()
				throw DaemonError.failed( "Still not answering. In Login Items switch Battery off and on again." )
			}
		}
	}

	/// An update swaps the app but not the running daemon: it keeps the old code, and a later respawn can fail on the stale job spec.
	/// Once per launch, when the versions differ, re-register so the new daemon takes over.
	private func restartOutdatedHelper( _ running: String ) {
		guard !restartedHelper, running != batteryFullVersion else { return }
		restartedHelper = true
		repairHelper()
	}

	/// Approved and registered, yet silent: the job is dead (gone from launchd, or "spawn failed" after the app was replaced) and
	/// nothing limits charging until someone clicks Repair. Don't wait for that click. Two polls in a row (~10s) so a helper that is
	/// merely slow to start isn't restarted; at most every 10 minutes so one that keeps dying isn't churned. Repair covers the gaps.
	private func healUnreachableHelper() {
		silentPolls += 1
		guard silentPolls >= 2, lastHeal.map( { Date().timeIntervalSince( $0 ) > 600 } ) ?? true else { return }
		lastHeal = Date()
		repairHelper()
	}

	/// Open at login is on by default: switched on once, so turning it off later sticks
	private func enableLoginItemOnce() {
		guard !defaults.bool( forKey: Pref.loginItemDefaulted ) else { return }
		defaults.set( true, forKey: Pref.loginItemDefaulted )
		try? SMAppService.mainApp.register()
		loginItem = SMAppService.mainApp.status == .enabled
	}

	func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

	private func setLaunchAtLogin( _ on: Bool ) {
		do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
		catch { self.error = error.localizedDescription }
		loginItem = SMAppService.mainApp.status == .enabled
	}

	// MARK: Knobs: controls backed by the daemon

	/// A control the daemon owns. On a click it shows the asked-for value and locks until the daemon has answered and
	/// the next snapshot is in; then it shows the truth again. Without this a switch bounces back for a beat and invites a second click.
	enum Knob: Hashable { case limitOn, limit, force, schedule, cli }
	private var pending: [ Knob: Any ] = [:]

	func isPending( _ k: Knob ) -> Bool { pending[ k ] != nil }
	private func shown<T>( _ k: Knob, _ truth: T ) -> T { pending[ k ] as? T ?? truth }

	private func flip<T>( _ k: Knob, to value: T, _ action: @escaping () async throws -> Void ) {
		guard pending[ k ] == nil else { return }
		pending[ k ] = value
		perform( action ) { [ weak self ] in self?.pending[ k ] = nil }
	}

	/// The popover switch
	var limitOn: Bool {
		get { shown( .limitOn, status?.maintain != nil ) }
		set { flip( .limitOn, to: newValue ) { [ self ] in try await client.send( newValue ? .maintain( .set( target, forceDischarge: force, enabled: true ) ) : .maintain( .stop ) ) } }
	}

	/// The slider. Edits show at once; they reach the daemon shortly after the last step, or on mouse release (see `limitChanged`).
	var limit: Int {
		get { shown( .limit, LimitSettings.limit( of: status?.limit ) ) }
		set { limitChanged( to: newValue ) }
	}

	var allowDischarge: Bool {
		get { shown( .force, status?.forceDischarge ?? true ) }
		set { flip( .force, to: newValue ) { [ self ] in try await client.send( .maintain( .set( target, forceDischarge: newValue && canCutAdapter, enabled: limitOn ) ) ) } }
	}

	var scheduleOn: Bool {
		get { shown( .schedule, ( status?.scheduleDays ?? 0 ) > 0 ) }
		set { flip( .schedule, to: newValue ) { [ self ] in try await client.send( .schedule( days: newValue ? 30 : 0 ) ) } }
	}

	var scheduleDays: Int {
		get { status?.scheduleDays ?? 0 }
		set { perform { [ self ] in try await client.send( .schedule( days: newValue ) ) } }
	}

	var cliInstalled: Bool {
		get { shown( .cli, status?.cliInstalled ?? false ) }
		set { flip( .cli, to: newValue ) { [ self ] in try await client.send( newValue ? .installCLI : .uninstallCLI ) } }
	}

	/// What the slider's number means as a band, and the discharge option as the daemon takes it
	private var target: MaintainTarget { LimitSettings.target( limit: limit ) }
	private var canCutAdapter: Bool { status?.canCutAdapter ?? false }
	private var force: Bool { allowDischarge && canCutAdapter }
	var dischargeTarget: Int { LimitSettings.dischargeTarget( limit: limit ) }

	private var limitCommit: Task<Void, Never>?
	/// Which edit a commit belongs to: only the latest one may stop showing the pending value
	private var limitEdits = 0

	/// Keyboard and VoiceOver steps never "end editing": they apply shortly after the last step. A mouse drag applies once, on
	/// release: while the button is held the pending apply waits, so a value passed on the way (a pause at 30% on the way to 80%)
	/// never reaches the helper. The button state, not onEditingChanged: on macOS that fires unreliably for drags (seen in e2e).
	/// The daemon remembers the limit also while the switch is off, so the slider is sent either way.
	func limitChanged( to n: Int ) {
		pending[ .limit ] = LimitSettings.sliderRange.clamp( n )
		limitEdits += 1
		let edit = limitEdits
		limitCommit?.cancel()
		limitCommit = Task { [ weak self ] in
			try? await Task.sleep( for: .milliseconds( 400 ) )
			while NSEvent.pressedMouseButtons & 1 != 0, !Task.isCancelled { try? await Task.sleep( for: .milliseconds( 50 ) ) }
			guard !Task.isCancelled, let self else { return }
			perform( { try await self.client.send( .maintain( .set( self.target, forceDischarge: self.force, enabled: self.limitOn ) ) ) } ) { [ weak self ] in
				if self?.limitEdits == edit { self?.pending[ .limit ] = nil }     // a newer edit is on its way: keep showing it
			}
		}
	}

	// MARK: Jobs

	func chargeTo( _ n: Int ) { perform { [ self ] in try await client.send( .charge( n ) ) } }
	func dischargeTo( _ n: Int ) { perform { [ self ] in try await client.send( .discharge( n ) ) } }
	func calibrate() { perform { [ self ] in try await client.send( .calibrate ) } }
	func recover() { perform { [ self ] in try await client.send( .maintain( .recover ) ) } }

	// MARK: v1 migration

	func removeLegacy() {
		perform { [ self ] in
			try await client.send( .removeLegacy )
			legacyLeftovers = []
		}
	}

	func declineLegacyCleanup() {
		defaults.set( true, forKey: Pref.legacyDeclined )
		legacyLeftovers = []
	}

	/// Settings -> "Uninstall": hand charging back to macOS, drop the helper.
	func uninstall() {
		perform { [ self ] in
			try? await client.send( .uninstall )
			try? await daemon.unregister()
			try? await SMAppService.mainApp.unregister()
			if let id = Bundle.main.bundleIdentifier { defaults.removePersistentDomain( forName: id ) }
			NSApplication.shared.terminate( nil )
		}
	}

	// MARK: Alerts

	private func checkLowBattery() {
		guard let s = status, defaults.bool( forKey: Pref.lowBatteryAlert ) else { return }
		let threshold = defaults.integer( forKey: Pref.lowBatteryLevel )

		if s.percent <= threshold, !s.acAttached {
			guard !alertedLow else { return }
			alertedLow = true
			let content = UNMutableNotificationContent()
			content.title = "Battery at \( s.percent )%"
			content.body = "Plug in soon."
			UNUserNotificationCenter.current().requestAuthorization( options: [ .alert, .sound ] ) { granted, _ in
				if granted { UNUserNotificationCenter.current().add( UNNotificationRequest( identifier: "low-battery", content: content, trigger: nil ) ) }
			}
		} else if s.percent > threshold + 3 || s.acAttached {
			alertedLow = false
		}
	}

	// MARK: Plumbing

	/// Run a daemon action: actions execute strictly in the order issued, failures surface and stay until dismissed,
	/// a fresh snapshot is in before `done` runs (so a knob never shows a stale truth in between).
	private func perform( _ action: @escaping () async throws -> Void, done: ( () -> Void )? = nil ) {
		inFlight += 1
		let previous = actionTail
		actionTail = Task { [ self ] in
			await previous?.value
			do { try await action(); error = nil } catch { self.error = error.localizedDescription }
			inFlight -= 1
			await refresh()
			done?()
		}
	}

	func dismissError() { error = nil }

}

/// Copy for each helper state, shared by the popover, the setup window and Settings. Strings are e2e anchors.
extension AppModel.Helper {

	/// Settings -> Helper -> Status
	var short: String {
		switch self {
		case .ready: return "Running"
		case .needsApproval: return "Needs approval"
		case .notRegistered: return "Not enabled"
		case .unreachable: return "Not responding"
		case .unknown: return "…"
		}
	}

	var title: String {
		switch self {
		case .needsApproval: return "Switch on Battery in Login Items"
		case .unreachable: return "Helper not responding"
		default: return "One-time setup required"
		}
	}

	var message: String {
		switch self {
		case .needsApproval: return "Battery's helper is waiting for your approval. Press the button below, then switch on Battery under App Background Activity."
		case .unreachable: return "The helper is registered but not answering (often after moving or replacing the app). Repair re-registers it and may ask for approval again."
		default: return "Battery needs a small background helper to control charging. Press the button below to open Login Items, then switch on Battery."
		}
	}

	var button: String { self == .unreachable ? "Repair helper" : "Open Login Items" }

}
