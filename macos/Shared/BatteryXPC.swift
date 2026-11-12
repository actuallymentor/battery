import Foundation

/// App, daemon and CLI all report the same version: MARKETING_VERSION, embedded in each binary's Info.plist.
let batteryVersion = Bundle.main.object( forInfoDictionaryKey: "CFBundleShortVersionString" ) as? String ?? "dev"
/// "2.0.0-beta.1 (42)": what the daemon reports, so the app also notices a rebuild of the same version
let batteryFullVersion = "\( batteryVersion ) (\( Bundle.main.object( forInfoDictionaryKey: "CFBundleVersion" ) as? String ?? "0" ))"

/// Daemon log file, world-readable
let batteryStateDir = "/var/db/co.palokaj.battery"
let batteryLogPath = "/Library/Logs/co.palokaj.battery.log"

/// Mach service name of the root daemon. Matches the launchd label.
let batteryDaemonName = "co.palokaj.battery.daemon"

/// App/CLI -> daemon. Every reply is ( ok, text ): text is output on success, a message on failure.
@objc( BatteryDaemonXPC ) protocol BatteryDaemonXPC {
	/// JSON of BatteryStatus
	func snapshot( reply: @escaping ( Bool, String ) -> Void )
	func probe( reply: @escaping ( Bool, String ) -> Void )
	func setCharging( _ on: Bool, reply: @escaping ( Bool, String ) -> Void )
	func maintain( _ setting: String, forceDischarge: Bool, reply: @escaping ( Bool, String ) -> Void )
	func stopMaintain( reply: @escaping ( Bool, String ) -> Void )
	func charge( _ percent: Int, reply: @escaping ( Bool, String ) -> Void )
	func discharge( _ percent: Int, reply: @escaping ( Bool, String ) -> Void )
	func calibrate( reply: @escaping ( Bool, String ) -> Void )
	/// v1 (shell + sudoers + LaunchAgent) leftovers present? Reply text: comma list of what was found, empty = none.
	func legacyFound( reply: @escaping ( Bool, String ) -> Void )
	func removeLegacy( reply: @escaping ( Bool, String ) -> Void )
	/// Restore normal charging and wipe persisted state (before the app unregisters the daemon).
	func resetAll( reply: @escaping ( Bool, String ) -> Void )
	/// Top off to 100% every N days (0 = off)
	func setSchedule( _ days: Int, reply: @escaping ( Bool, String ) -> Void )
	/// Symlink /usr/local/bin/battery to the CLI inside /Applications/Battery.app (root-owned location only)
	func installCLI( reply: @escaping ( Bool, String ) -> Void )
	func uninstallCLI( reply: @escaping ( Bool, String ) -> Void )
	func setAdapter( _ on: Bool, reply: @escaping ( Bool, String ) -> Void )
	/// Full removal: restore charging, forget the schedule, drop the CLI link, delete persisted state and the log. The app unregisters the daemon right after.
	func uninstall( reply: @escaping ( Bool, String ) -> Void )
}
