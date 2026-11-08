import Foundation

/// Mach service name of the root daemon. Matches the launchd label.
let batteryDaemonName = "co.palokaj.battery.daemon"

/// App/CLI -> daemon. Every reply is ( ok, text ): text is output on success, a message on failure.
@objc( BatteryDaemonXPC ) protocol BatteryDaemonXPC {
	func probe( reply: @escaping ( Bool, String ) -> Void )
	func status( reply: @escaping ( Bool, String ) -> Void )
	func setCharging( _ on: Bool, reply: @escaping ( Bool, String ) -> Void )
	func maintain( _ setting: String, forceDischarge: Bool, reply: @escaping ( Bool, String ) -> Void )
	func stopMaintain( reply: @escaping ( Bool, String ) -> Void )
	func statusCSV( reply: @escaping ( Bool, String ) -> Void )
	func setAdapter( _ on: Bool, reply: @escaping ( Bool, String ) -> Void )
}
