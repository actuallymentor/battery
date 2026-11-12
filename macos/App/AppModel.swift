import Foundation
import SwiftUI
import ServiceManagement
import UserNotifications
import BatteryCore

/// State + actions for every view. One poll loop; the daemon is the source of truth.
@MainActor
@Observable
final class AppModel {

	enum Helper: Equatable { case unknown, ready, notRegistered, needsApproval, unreachable }

	private( set ) var status: BatteryStatus?
	private( set ) var helper: Helper = .unknown
	private( set ) var error: String?
	/// Last known truth while the helper answered: a limit that holds charging off keeps doing so with no helper to lift it.
	private( set ) var limitWasActive = false
	/// Actions in flight. Polling pauses while > 0 so an old snapshot can't overwrite a fresh change.
	private var inFlight = 0
	var busy: Bool { inFlight > 0 }

	/// What the popover edits. Persisted per user; the daemon's own target wins on first contact and on outside changes.
	var settings = LimitSettings.load() { didSet { settings.save() } }
	private( set ) var legacyLeftovers: [ String ] = []

	/// Launch at login for the menu bar app itself
	private( set ) var launchAtLogin = SMAppService.mainApp.status == .enabled

	private let client = DaemonClient()
	private let daemon = SMAppService.daemon( plistName: "co.palokaj.battery.daemon.plist" )
	private let defaults = UserDefaults.standard
	private var poll: Task<Void, Never>?
	private var alertedLow = false
	private var restartedHelper = false
	/// Auto-repair of a registered helper that stopped answering: after two silent polls in a row, at most every 10 minutes
	private var lastHeal: Date?
	private var silentPolls = 0
	/// Last target we adopted or sent: a different one in the daemon means someone else (CLI, reboot) changed it.
	private var knownTarget: String?
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
		launchAtLogin = SMAppService.mainApp.status == .enabled
		guard inFlight == 0 else { return }

		do {
			let fresh = try await client.snapshot()
			guard inFlight == 0 else { return }     // an action started while we waited: this snapshot is already stale
			status = fresh
			limitWasActive = fresh.maintain != nil
			silentPolls = 0
			restartOutdatedHelper( fresh.daemonVersion )
			adoptOutsideChanges()
			helper = .ready
			error = nil
			checkLowBattery()
			if legacyLeftovers.isEmpty, !defaults.bool( forKey: Pref.legacyDeclined ) { legacyLeftovers = ( try? await client.legacyFound() ) ?? [] }
		} catch {
			// Not answering: find out why
			status = nil
			switch daemon.status {
			case .notRegistered, .notFound: helper = .notRegistered
			case .requiresApproval: helper = .needsApproval
			default: helper = .unreachable; healUnreachableHelper()
			}
		}
	}

	// MARK: Helper lifecycle

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
	func repairHelper() {
		Task {
			var answering = false
			for _ in 0..<2 {
				try? await daemon.unregister()
				try? await Task.sleep( for: .seconds( 1 ) )
				do { try daemon.register() } catch { self.error = error.localizedDescription }
				if daemon.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems(); break }

				try? await Task.sleep( for: .seconds( 4 ) )
				answering = ( try? await client.snapshot() ) != nil
				if answering { break }
			}
			if !answering, daemon.status == .enabled {
				error = "Still not answering. In Login Items switch Battery off and on again."
				SMAppService.openSystemSettingsLoginItems()
			}
			await refresh()
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
		launchAtLogin = SMAppService.mainApp.status == .enabled
	}

	func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

	func setLaunchAtLogin( _ on: Bool ) {
		do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
		catch { self.error = error.localizedDescription }
		launchAtLogin = SMAppService.mainApp.status == .enabled
	}

	// MARK: Limit

	func applyLimit( enabled: Bool ) {
		perform { [ self ] in
			if enabled {
				let t = settings.target
				knownTarget = t.persisted
				try await client.maintain( t, force: settings.force && ( status?.canCutAdapter ?? false ) )   // the default is on; Macs without an adapter-cut key just ignore it
			} else {
				knownTarget = nil
				try await client.stopMaintain()
			}
		}
	}

	/// Re-send the band after a value changed while the limit is on.
	func commitLimitChange() { if status?.maintain != nil { applyLimit( enabled: true ) } }

	private var limitCommit: Task<Void, Never>?

	/// Keyboard and VoiceOver steps never "end editing": they apply shortly after the last step. A mouse drag applies once, on
	/// release: while the button is held the pending apply waits, so a value passed on the way (a pause at 30% on the way to 80%)
	/// never reaches the helper. The button state, not onEditingChanged: on macOS that fires unreliably for drags (seen in e2e).
	func limitChanged( to n: Int ) {
		settings.setLimit( n )
		limitCommit?.cancel()
		limitCommit = Task { [ weak self ] in
			try? await Task.sleep( for: .milliseconds( 400 ) )
			while NSEvent.pressedMouseButtons & 1 != 0, !Task.isCancelled { try? await Task.sleep( for: .milliseconds( 50 ) ) }
			if !Task.isCancelled { self?.commitLimitChange() }
		}
	}

	/// The daemon owns the real limit (it persists across reboots, the CLI can change it). When its target differs from the
	/// last one we know, show that instead of stale edits.
	private func adoptOutsideChanges() {
		let current = status?.maintain
		guard current != knownTarget else { return }
		knownTarget = current
		if let t = status?.maintainTarget { settings.adopt( t, force: ( status?.canCutAdapter ?? false ) ? ( status?.forceDischarge ?? false ) : settings.force ) }
	}

	// MARK: Jobs

	func setSchedule( days: Int ) { perform { [ self ] in try await client.setSchedule( days ) } }
	func chargeTo( _ n: Int ) { perform { [ self ] in try await client.charge( n ) } }
	func dischargeTo( _ n: Int ) { perform { [ self ] in try await client.discharge( n ) } }
	func calibrate() { perform { [ self ] in try await client.calibrate() } }
	func recover() { perform { [ self ] in try await client.resetAll() } }

	// MARK: Command line

	var cliInstalled: Bool { ( try? FileManager.default.destinationOfSymbolicLink( atPath: "/usr/local/bin/battery" ) ) == "/Applications/Battery.app/Contents/Helpers/battery" }

	func setCLIInstalled( _ on: Bool ) {
		perform { [ self ] in if on { try await client.installCLI() } else { try await client.uninstallCLI() } }
	}

	// MARK: v1 migration

	func removeLegacy() {
		perform { [ self ] in
			try await client.removeLegacy()
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
			try? await client.uninstall()
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

	/// Run a daemon action: actions execute strictly in the order issued, failures surface, polling resumes afterwards.
	private func perform( _ action: @escaping () async throws -> Void ) {
		inFlight += 1
		let previous = actionTail
		actionTail = Task { [ self ] in
			await previous?.value
			do { try await action(); error = nil } catch { self.error = error.localizedDescription }
			inFlight -= 1
			await refresh()
		}
	}

	func dismissError() { error = nil }

}
