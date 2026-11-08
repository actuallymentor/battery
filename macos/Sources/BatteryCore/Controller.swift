import Foundation

public enum LEDColor: Equatable, Sendable { case green, orange, off }

/// What the maintain loop wants done this tick.
public struct Decision: Equatable, Sendable {
	public enum Action: Equatable, Sendable { case enableCharging, disableCharging, none }
	public var action: Action
	public var led: LEDColor?
	/// New value for the "refilling to upper" latch; nil = leave as is
	public var refilling: Bool?
	public static let idle = Decision( action: .none, led: nil )

	public init( action: Action, led: LEDColor?, refilling: Bool? = nil ) {
		self.action = action
		self.led = led
		self.refilling = refilling
	}
}

/// Snapshot of the battery; `chargingEnabled` is nil when SMC state is unreadable.
public struct BatteryState: Equatable, Sendable {
	public var percent: Int
	public var voltage: Double?
	public var chargingEnabled: Bool?
	public var acAttached: Bool

	/// We resumed charging below `lower` and have not reached `upper` yet. Inside the band, this decides
	/// between "keep charging up" and "hold" (#475: plugging in inside the band must not charge to the top).
	public var refilling: Bool

	public init( percent: Int, voltage: Double? = nil, chargingEnabled: Bool?, acAttached: Bool, refilling: Bool = false ) {
		self.refilling = refilling
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
			return Decision( action: s.chargingEnabled == true ? .disableCharging : .none, led: .green, refilling: false )
		}

		// Below the bottom: charge (resume if held off, otherwise remember we are refilling)
		if s.percent < lower {
			if s.chargingEnabled == false { return Decision( action: .enableCharging, led: .orange, refilling: true ) }
			return s.chargingEnabled == true && !s.refilling ? Decision( action: .none, led: nil, refilling: true ) : .idle
		}

		// Inside the band: keep charging only if we are on the way up from below `lower`, otherwise hold
		if lower < upper, s.chargingEnabled == true, !s.refilling {
			return Decision( action: .disableCharging, led: .green )
		}

		return .idle

	}

	private static func decideVoltage( center: Double, hysteresis: Double, _ s: BatteryState ) -> Decision {
		guard let v = s.voltage else { return .idle }

		if v < center - hysteresis && s.chargingEnabled == false { return Decision( action: .enableCharging, led: nil ) }
		if v >= center + hysteresis && s.chargingEnabled == true { return Decision( action: .disableCharging, led: nil ) }

		return .idle
	}

	/// `--force-discharge`: cut the adapter while above the band, restore once back inside it.
	/// A cut adapter makes macOS report "not on AC", so `currentlyCut` must keep the decision stable (no flapping every tick).
	public static func forceDischargeCut( percent: Int, upper: Int, acAttached: Bool, currentlyCut: Bool ) -> Bool {
		percent > upper && ( acAttached || currentlyCut )
	}

	/// Requested vs effective: we hold charging off, yet current still flows into the pack.
	/// `heldFor` is how long the hold has been in place (firmware needs ~45 s to act).
	public static func effectWarning( heldFor: TimeInterval?, chargingEnabled: Bool?, acAttached: Bool, isCharging: Bool?, amperage: Int? ) -> String? {
		guard let heldFor, heldFor > 120, chargingEnabled == false, acAttached, isCharging == true, ( amperage ?? 0 ) > 100 else { return nil }
		return "macOS is still charging even though the limit is set. This Mac may be ignoring the charge control."
	}

	/// Seconds to sleep between `charge N` polls: slow far away, fast near the target.
	public static func chargePollInterval( percent: Int, target: Int ) -> TimeInterval {
		percent >= target - 3 ? 20 : 60
	}

	public static let maintainPollInterval: TimeInterval = 60

}
