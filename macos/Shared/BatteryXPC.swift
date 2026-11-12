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

/// App/CLI -> daemon. Two calls: read everything, or run one `Command` (JSON, see BatteryCore). Every reply is
/// ( ok, text ): text is output on success, a message on failure. A new action is a `Command` case plus its branch in the daemon.
@objc( BatteryDaemonXPC ) protocol BatteryDaemonXPC {
	/// JSON of BatteryStatus
	func snapshot( reply: @escaping ( Bool, String ) -> Void )
	/// JSON of Command
	func run( _ command: String, reply: @escaping ( Bool, String ) -> Void )
}
