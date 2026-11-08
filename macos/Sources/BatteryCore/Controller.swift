import Foundation

public enum LEDColor: Equatable, Sendable { case green, orange, off }

/// What the maintain loop wants done this tick.
public struct Decision: Equatable, Sendable {
	public enum Action: Equatable, Sendable { case enableCharging, disableCharging, none }
	public var action: Action
	public var led: LEDColor?
	public static let idle = Decision( action: .none, led: nil )
}

/// Snapshot of the battery; `chargingEnabled` is nil when SMC state is unreadable.
public struct BatteryState: Equatable, Sendable {
	public var percent: Int
	public var voltage: Double?
	public var chargingEnabled: Bool?
	public var acAttached: Bool

	public init( percent: Int, voltage: Double? = nil, chargingEnabled: Bool?, acAttached: Bool ) {
		self.percent = percent
		self.voltage = voltage
		self.chargingEnabled = chargingEnabled
		self.acAttached = acAttached
	}
}

public enum Controller {

	/// One tick of `maintain`. Pure: state in, decision out.
	public static func decide( _ target: MaintainTarget, _ state: BatteryState ) -> Decision {
		switch target {
		case .level( let lower, let upper ): return decideLevel( lower: lower, upper: upper, state )
		case .voltage( let center, let hyst ): return decideVoltage( center: center, hysteresis: hyst, state )
		}
	}

	private static func decideLevel( lower: Int, upper: Int, _ s: BatteryState ) -> Decision {

		// At or above the top: stop charging (even if SMC says off but AC is attached, keep LED green)
		if s.percent >= upper && ( s.chargingEnabled == true || s.acAttached ) {
			return Decision( action: s.chargingEnabled == true ? .disableCharging : .none, led: .green )
		}

		// Below the bottom while held off: resume charging
		if s.percent < lower && s.chargingEnabled == false {
			return Decision( action: .enableCharging, led: .orange )
		}

		return .idle

	}

	private static func decideVoltage( center: Double, hysteresis: Double, _ s: BatteryState ) -> Decision {
		guard let v = s.voltage else { return .idle }

		if v < center - hysteresis && s.chargingEnabled == false { return Decision( action: .enableCharging, led: nil ) }
		if v >= center + hysteresis && s.chargingEnabled == true { return Decision( action: .disableCharging, led: nil ) }

		return .idle
	}

	/// Seconds to sleep between `charge N` polls: slow far away, fast near the target.
	public static func chargePollInterval( percent: Int, target: Int ) -> TimeInterval {
		percent >= target - 3 ? 20 : 60
	}

	public static let maintainPollInterval: TimeInterval = 60

}
