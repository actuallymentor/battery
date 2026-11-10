import Foundation

/// The real `battery` CLI shipped inside the installed app, talking to the real root helper over XPC.
public enum CLI {

	public static let path = ProcessInfo.processInfo.environment[ "E2E_CLI" ] ?? "/Applications/Battery.app/Contents/Helpers/battery"

	@discardableResult
	public static func battery( _ args: String..., timeout: TimeInterval = 30 ) -> Result { sh( path, args, timeout: timeout ) }

	public static func battery( _ args: [ String ], timeout: TimeInterval = 30 ) -> Result { sh( path, args, timeout: timeout ) }

	/// `status_csv`: percent,remaining,charging,discharging,maintain
	public struct Csv {
		public let percent: Int, remaining: String, charging: String, discharging: String, maintain: String
		public var chargingEnabled: Bool { charging == "enabled" }
	}

	public static func csv() -> Csv? {
		let f = battery( "status_csv" ).out.split( separator: ",", omittingEmptySubsequences: false ).map( String.init )
		guard f.count >= 5, let pct = Int( f[ 0 ] ) else { return nil }
		return Csv( percent: pct, remaining: f[ 1 ], charging: f[ 2 ], discharging: f[ 3 ], maintain: f[ 4 ] )
	}

	/// Back to a neutral Mac: no limit, no job, no schedule, charging and adapter on.
	public static func restore() {
		battery( "maintain", "recover" )
		battery( "schedule", "0" )
		battery( "charging", "on" )
		battery( "adapter", "on" )
	}

}
