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
	private( set ) var busy = false
	private( set ) var legacyLeftovers: [ String ] = []

	/// Launch at login for the menu bar app itself
	private( set ) var launchAtLogin = SMAppService.mainApp.status == .enabled

	private let client = DaemonClient()
	private let daemon = SMAppService.daemon( plistName: "co.palokaj.battery.daemon.plist" )
	private let defaults = UserDefaults.standard
	private var poll: Task<Void, Never>?
	private var alertedLow = false
	private var adopted = false

	init() {
		UserDefaults.registerBatteryDefaults()
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

		do {
			status = try await client.snapshot()
			adoptDaemonLimitOnce()
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
			default: helper = .unreachable
			}
		}
	}

	// MARK: Helper lifecycle

	func registerHelper() {
		do { try daemon.register() } catch { self.error = error.localizedDescription }
		if daemon.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
		Task { await refresh() }
	}

	/// Registered but not answering (app was moved, bundle replaced, stale registration): start over.
	func repairHelper() {
		Task {
			try? await daemon.unregister()
			try? await Task.sleep( for: .seconds( 1 ) )
			registerHelper()
		}
	}

	func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

	func setLaunchAtLogin( _ on: Bool ) {
		do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
		catch { self.error = error.localizedDescription }
		launchAtLogin = SMAppService.mainApp.status == .enabled
	}

	// MARK: Limit

	var limit: Int { get { defaults.integer( forKey: Pref.limit ) } set { defaults.set( newValue, forKey: Pref.limit ) } }
	var lower: Int { get { defaults.integer( forKey: Pref.lower ) } set { defaults.set( newValue, forKey: Pref.lower ) } }
	var forceDischarge: Bool { get { defaults.bool( forKey: Pref.forceDischarge ) } set { defaults.set( newValue, forKey: Pref.forceDischarge ) } }

	func applyLimit( enabled: Bool ) {
		perform { [ self ] in
			if enabled {
				let t: MaintainTarget = lower < limit ? .level( lower: max( lower, 10 ), upper: limit ) : .level( lower: limit, upper: limit )
				try await client.maintain( t, force: forceDischarge )
			} else {
				try await client.stopMaintain()
			}
		}
	}

	/// Re-send the band after a value changed while the limit is on.
	func commitLimitChange() { if status?.maintain != nil { applyLimit( enabled: true ) } }

	/// The daemon owns the real limit (it persists across reboots). First contact: show that, not stale prefs.
	private func adoptDaemonLimitOnce() {
		guard !adopted else { return }
		adopted = true
		if case .level( let l, let u )? = status?.maintainTarget { limit = u; lower = l; forceDischarge = status?.forceDischarge ?? false }
	}

	// MARK: Jobs

	func setSchedule( days: Int ) { perform { [ self ] in try await client.setSchedule( days ) } }
	func chargeTo( _ n: Int ) { perform { [ self ] in try await client.charge( n ) } }
	func dischargeTo( _ n: Int ) { perform { [ self ] in try await client.discharge( n ) } }
	func calibrate() { perform { [ self ] in try await client.calibrate() } }
	func recover() { perform { [ self ] in try await client.recover() } }

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
			try? await client.uninstallCLI()
			try? await client.resetAll()
			try? await daemon.unregister()
			try? await SMAppService.mainApp.unregister()
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

	/// Run a daemon action, surface failures, then refresh.
	private func perform( _ action: @escaping () async throws -> Void ) {
		busy = true
		Task {
			do { try await action(); error = nil } catch { self.error = error.localizedDescription }
			busy = false
			await refresh()
		}
	}

	func dismissError() { error = nil }

}
