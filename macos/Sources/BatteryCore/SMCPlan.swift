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
	public static let probeKeys = [ "CHTE", "CH0B", "CH0C", "CHIE", "CH0I", "CH0J", "ACLC", "bfD0", "bfE0", "bfF0" ]

	/// How charging can be held on this machine. Chosen by which keys exist, never by OS version
	/// (key availability moved around 15.8.x / 26.x / 27 and reports contradict any version gate).
	public enum Backend: String, Codable, Equatable, Sendable {
		case legacy         // CH0B / CH0C inhibit
		case tahoe          // CHTE inhibit
		case firmwareLimit  // bfD0 / bfE0 / bfF0: firmware holds a % limit itself
		case softwareCut    // adapter cut at the limit (CHIE / CH0J / CH0I): compat mode, burns battery cycles
		case none

		/// Settings -> Charge control
		public var title: String {
			switch self {
			case .tahoe, .legacy: return "SMC inhibit"
			case .firmwareLimit: return "Firmware limit"
			case .softwareCut: return "Adapter cut (compatibility)"
			case .none: return "Not supported"
			}
		}
	}

	public var backend: Backend {
		if tahoe { return .tahoe }      // v1 order: CHTE wins when both exist
		if legacy { return .legacy }
		if keys.isSuperset( of: [ "bfD0", "bfE0", "bfF0" ] ) { return .firmwareLimit }
		if adapterCHIE || adapterCH0J || keys.contains( "CH0I" ) { return .softwareCut }
		return .none
	}

	/// Is there any way to cut the adapter ( `battery adapter off`, force discharge )?
	public var canCutAdapter: Bool { adapterCHIE || adapterCH0J || keys.contains( "CH0I" ) }

	public var summary: String {
		"SMC capabilities: backend=\(backend.rawValue) tahoe=\(tahoe) legacy=\(legacy) CHIE=\(adapterCHIE) CH0I=\(keys.contains( "CH0I" )) CH0J=\(adapterCH0J) bf=\(keys.isSuperset( of: [ "bfD0", "bfE0", "bfF0" ] ))"
	}

}

/// Translates intent ("charging off") to SMC writes for the keys that exist.
/// Values mirror v1 `battery.sh` so behaviour stays identical on known hardware.
public enum SMCPlan {

	/// Nil when this machine has no way to hold charging (or, for the firmware limit, when the current level is needed and unknown).
	/// `level` is the current battery %, used to freeze the firmware limit in place.
	public static func charging( _ enabled: Bool, _ caps: SMCCapabilities, level: Int? = nil ) -> [ SMCWrite ]? {
		switch caps.backend {
		case .tahoe: return [ SMCWrite( "CHTE", enabled ? "00000000" : "01000000" ) ]
		case .legacy: let v = enabled ? "00" : "02"; return [ SMCWrite( "CH0B", v ), SMCWrite( "CH0C", v ) ]
		case .firmwareLimit:
			if enabled { return firmwareReset }
			// Hold: limit == current level means pass-through at 0 mA; a lower limit would drain
			guard let level else { return nil }
			return level >= 100 ? [] : firmwareLimit( upper: level, lower: level )
		case .softwareCut: return adapter( on: enabled, caps )
		case .none: return nil
		}
	}

	// MARK: Firmware limit ( bfD0 / bfE0 / bfF0 )

	/// Lowest limit we will write: below this the firmware drains the pack on purpose (#485).
	public static let firmwareFloor = 20

	/// Little-endian uint32 as the 8 hex chars the SMC expects: 80 -> "50000000".
	public static func le32( _ n: Int ) -> String {
		( 0..<4 ).map { String( format: "%02x", ( n >> ( 8 * $0 ) ) & 0xff ) }.joined()
	}

	/// Write order that works across reports: disable, set both bounds, enable.
	/// `lower` is when charging resumes; the firmware wants lower < upper, so a single value N resumes at N-2.
	/// Nil when the request is unsafe or pointless ( upper >= 100 = no limit ).
	public static func firmwareLimit( upper: Int, lower: Int ) -> [ SMCWrite ]? {
		guard upper >= firmwareFloor, upper < 100 else { return nil }
		let resume = lower >= upper ? upper - 2 : lower
		let low = max( firmwareFloor, min( resume, upper - 1 ) )
		return [ SMCWrite( "bfF0", "00" ), SMCWrite( "bfD0", le32( upper ) ), SMCWrite( "bfE0", le32( low ) ), SMCWrite( "bfF0", "02" ) ]
	}

	/// Back to "firmware does not limit". Used on stop, uninstall and rollback.
	public static let firmwareReset = [ SMCWrite( "bfF0", "00" ), SMCWrite( "bfD0", "00000000" ), SMCWrite( "bfE0", "00000000" ) ]

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
		switch caps.backend {
		case .tahoe, .legacy:
			let key = caps.tahoe ? "CHTE" : "CH0B"
			guard let hex = read( key ), !hex.isEmpty else { return nil }
			return hex == ( key == "CHTE" ? "00000000" : "00" )
		case .firmwareLimit:
			guard let hex = read( "bfF0" ), !hex.isEmpty else { return nil }
			return hex == "00"      // limit switched off = charging allowed
		case .softwareCut:
			return discharging( caps, read: read ).map { !$0 }
		case .none: return nil
		}
	}

	/// Read side: adapter cut (discharging while plugged in)? Nil = unknown.
	public static func discharging( _ caps: SMCCapabilities, read: ( String ) -> String? ) -> Bool? {
		let key = caps.adapterCHIE ? "CHIE" : caps.adapterCH0J ? "CH0J" : "CH0I"
		guard let hex = read( key ), !hex.isEmpty else { return nil }
		return hex != "0" && hex != "00"
	}

}
