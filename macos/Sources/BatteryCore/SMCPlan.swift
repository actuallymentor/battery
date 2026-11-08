import Foundation

public struct SMCWrite: Equatable, Sendable {
	public var key: String
	public var hex: String
	public init( _ key: String, _ hex: String ) { self.key = key; self.hex = hex }
}

/// Which SMC keys this machine answers to. Filled by probing in the daemon; never assumed per OS version.
public struct SMCCapabilities: Equatable, Sendable {

	public var keys: Set<String>

	public init( keys: Set<String> ) { self.keys = keys }

	public var tahoe: Bool { keys.contains( "CHTE" ) }
	public var legacy: Bool { keys.contains( "CH0B" ) }
	public var adapterCHIE: Bool { keys.contains( "CHIE" ) }
	public var adapterCH0J: Bool { keys.contains( "CH0J" ) }

	/// Keys we know how to probe
	public static let probeKeys = [ "CHTE", "CH0B", "CH0C", "CHIE", "CH0I", "CH0J", "ACLC" ]

	public var summary: String {
		"SMC capabilities: tahoe=\(tahoe) legacy=\(legacy) CHIE=\(adapterCHIE) CH0I=\(keys.contains( "CH0I" )) CH0J=\(adapterCH0J)"
	}

}

/// Translates intent ("charging off") to SMC writes for the keys that exist.
/// Values mirror v1 `battery.sh` so behaviour stays identical on known hardware.
public enum SMCPlan {

	/// Nil when no known charging key exists.
	public static func charging( _ enabled: Bool, _ caps: SMCCapabilities ) -> [ SMCWrite ]? {
		if caps.tahoe { return [ SMCWrite( "CHTE", enabled ? "00000000" : "01000000" ) ] }
		if caps.legacy { let v = enabled ? "00" : "02"; return [ SMCWrite( "CH0B", v ), SMCWrite( "CH0C", v ) ] }
		return nil
	}

	/// `adapterOn: false` = cut the adapter so the battery discharges while plugged in.
	public static func adapter( on: Bool, _ caps: SMCCapabilities ) -> [ SMCWrite ] {
		let key = caps.adapterCHIE ? "CHIE" : caps.adapterCH0J ? "CH0J" : "CH0I"
		let value = on ? "00" : ( key == "CHIE" ? "08" : "01" )
		return [ SMCWrite( key, value ) ]
	}

	public static func led( _ color: LEDColor ) -> SMCWrite {
		switch color {
		case .green: return SMCWrite( "ACLC", "03" )
		case .orange: return SMCWrite( "ACLC", "04" )
		case .off: return SMCWrite( "ACLC", "00" )
		}
	}

	/// Read side: charging enabled? Nil = unknown.
	public static func chargingEnabled( _ caps: SMCCapabilities, read: ( String ) -> String? ) -> Bool? {
		let key = caps.tahoe ? "CHTE" : "CH0B"
		guard let hex = read( key ), !hex.isEmpty else { return nil }
		return hex == ( caps.tahoe ? "00000000" : "00" )
	}

	/// Read side: adapter cut (discharging while plugged in)? Nil = unknown.
	public static func discharging( _ caps: SMCCapabilities, read: ( String ) -> String? ) -> Bool? {
		let key = caps.adapterCHIE ? "CHIE" : caps.adapterCH0J ? "CH0J" : "CH0I"
		guard let hex = read( key ), !hex.isEmpty else { return nil }
		return hex != "0" && hex != "00"
	}

}
