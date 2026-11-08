import Foundation

/// Everything the app needs in one daemon round trip. JSON over XPC.
public struct BatteryStatus: Codable, Equatable, Sendable {

	public var percent: Int
	public var voltage: Double?
	public var remaining: String
	public var acAttached: Bool

	/// SMC says charging is allowed / adapter is cut. Nil = unreadable on this machine.
	public var chargingEnabled: Bool?
	public var discharging: Bool?

	/// `MaintainTarget.persisted` form, nil when not maintaining
	public var maintain: String?
	public var forceDischarge: Bool

	/// Running job ("Charging to 90%"), nil when idle
	public var activity: String?

	/// Probed SMC keys that exist, for diagnostics and capability gating
	public var smcKeys: [ String ]

	public var daemonVersion: String

	/// How this Mac holds charging (`SMCCapabilities.Backend` raw value)
	public var backend: String

	/// Observed, not requested: is current actually flowing into the pack, and how much (mA, + = charging)
	public var isCharging: Bool?
	public var amperage: Int?

	/// Set when what we asked for is not what the hardware does
	public var warning: String?

	/// Battery health (PR #445)
	public var cycleCount: Int?
	public var healthPercent: Int?

	public init( percent: Int, voltage: Double? = nil, remaining: String = "no estimate", acAttached: Bool,
	             chargingEnabled: Bool? = nil, discharging: Bool? = nil, maintain: String? = nil, forceDischarge: Bool = false,
	             activity: String? = nil, smcKeys: [ String ] = [], daemonVersion: String = "",
	             backend: String = "unknown", isCharging: Bool? = nil, amperage: Int? = nil, warning: String? = nil,
	             cycleCount: Int? = nil, healthPercent: Int? = nil ) {
		self.cycleCount = cycleCount
		self.healthPercent = healthPercent
		self.backend = backend
		self.isCharging = isCharging
		self.amperage = amperage
		self.warning = warning
		self.percent = percent
		self.voltage = voltage
		self.remaining = remaining
		self.acAttached = acAttached
		self.chargingEnabled = chargingEnabled
		self.discharging = discharging
		self.maintain = maintain
		self.forceDischarge = forceDischarge
		self.activity = activity
		self.smcKeys = smcKeys
		self.daemonVersion = daemonVersion
	}

	public var maintainTarget: MaintainTarget? { maintain.flatMap { try? MaintainTarget( persisted: $0 ) } }

	/// One-line state for the popover header
	public var headline: String {
		if let activity { return activity }
		if backend == "none" { return "Limiting not supported" }
		if discharging == true { return "Discharging on adapter" }
		if !acAttached { return "On battery" }
		if chargingEnabled == false { return maintain != nil ? "Holding at limit" : "Charging paused" }
		if percent >= 100 { return "Fully charged" }
		return "Charging"
	}

	public func encoded() -> String {
		( try? JSONEncoder().encode( self ) ).flatMap { String( data: $0, encoding: .utf8 ) } ?? "{}"
	}

	public static func decode( _ json: String ) -> BatteryStatus? {
		try? JSONDecoder().decode( BatteryStatus.self, from: Data( json.utf8 ) )
	}

}
