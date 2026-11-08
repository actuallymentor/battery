import Foundation

/// Single source for the version shown by CLI, daemon and app. Keep in sync with MARKETING_VERSION in project.yml.
let batteryVersion = "2.0.0-dev"

/// Daemon log file, world-readable
let batteryLogPath = "/Library/Logs/co.palokaj.battery.log"

/// Mach service name of the root daemon. Matches the launchd label.
let batteryDaemonName = "co.palokaj.battery.daemon"

/// App/CLI -> daemon. Every reply is ( ok, text ): text is output on success, a message on failure.
@objc( BatteryDaemonXPC ) protocol BatteryDaemonXPC {
	/// JSON of BatteryStatus
	func snapshot( reply: @escaping ( Bool, String ) -> Void )
	func probe( reply: @escaping ( Bool, String ) -> Void )
	func status( reply: @escaping ( Bool, String ) -> Void )
	func setCharging( _ on: Bool, reply: @escaping ( Bool, String ) -> Void )
	func maintain( _ setting: String, forceDischarge: Bool, reply: @escaping ( Bool, String ) -> Void )
	func stopMaintain( reply: @escaping ( Bool, String ) -> Void )
	func statusCSV( reply: @escaping ( Bool, String ) -> Void )
	func charge( _ percent: Int, reply: @escaping ( Bool, String ) -> Void )
	func discharge( _ percent: Int, reply: @escaping ( Bool, String ) -> Void )
	func calibrate( reply: @escaping ( Bool, String ) -> Void )
	func recover( reply: @escaping ( Bool, String ) -> Void )
	/// v1 (shell + sudoers + LaunchAgent) leftovers present? Reply text: comma list of what was found, empty = none.
	func legacyFound( reply: @escaping ( Bool, String ) -> Void )
	func removeLegacy( reply: @escaping ( Bool, String ) -> Void )
	/// Restore normal charging and wipe persisted state (before the app unregisters the daemon).
	func resetAll( reply: @escaping ( Bool, String ) -> Void )
	func setAdapter( _ on: Bool, reply: @escaping ( Bool, String ) -> Void )
}
