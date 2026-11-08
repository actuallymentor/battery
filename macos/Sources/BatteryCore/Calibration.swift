import Foundation

/// Calibration: discharge to 15%, charge to 100%, hold 1h, discharge to 80%, restore maintenance.
/// Pure state machine; the daemon feeds it percent + clock and applies `phase` side effects.
public struct Calibration: Equatable, Sendable {

	public enum Phase: Equatable, Sendable {
		case discharging15, charging100, holding, discharging80, done

		public var message: String {
			switch self {
			case .discharging15: return "[ 1 ] Discharging battery to 15%"
			case .charging100: return "[ 2 ] Charging to 100%"
			case .holding: return "[ 3 ] Reached 100%, waiting for 1 hour"
			case .discharging80: return "[ 4 ] Discharging battery to 80%"
			case .done: return "[ 5 ] Restarting battery maintenance"
			}
		}
	}

	public static let holdDuration: TimeInterval = 3600

	public private(set) var phase: Phase = .discharging15
	private var holdStart: Date?

	public init() {}

	/// Feed the latest reading. Returns true when the phase changed.
	@discardableResult
	public mutating func advance( percent: Int, now: Date ) -> Bool {
		let before = phase

		switch phase {
		case .discharging15: if percent <= 15 { phase = .charging100 }
		case .charging100: if percent >= 100 { phase = .holding; holdStart = now }
		case .holding: if let holdStart, now.timeIntervalSince( holdStart ) >= Self.holdDuration { phase = .discharging80 }
		case .discharging80: if percent <= 80 { phase = .done }
		case .done: break
		}

		return phase != before
	}

}
