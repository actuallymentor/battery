import Foundation

/// One-shot jobs the daemon runs: `charge N`, `discharge N`, `calibrate`.
public enum Job: Equatable, Sendable {
	case charge( Int )
	case discharge( Int )
	case calibrate( Calibration )

	/// Line for `status` / the popover
	public var activity: String {
		switch self {
		case .charge( let n ): return "Charging to \( n )%"
		case .discharge( let n ): return "Discharging to \( n )%"
		case .calibrate( let c ): return "Calibrating: \( c.phase.message )"
		}
	}
}

/// What a job wants done to the hardware. The daemon turns these into SMC writes.
public enum Intent: Equatable, Sendable {
	case adapter( on: Bool )
	case charging( on: Bool, holdAtLevel: Int? )
}

public struct JobStep: Equatable, Sendable {
	public var job: Job
	public var intents: [ Intent ]
	public var finished: Bool
}

/// Pure job logic: percent + clock in, intents out. No SMC, no timers, so every rule is testable on Linux.
public enum JobPlanner {

	/// Intents when a job begins.
	public static func start( _ job: Job ) -> [ Intent ] {
		switch job {
		case .charge: return charging
		case .discharge: return [ .adapter( on: false ) ]
		case .calibrate( let c ): return intents( for: c.phase )
		}
	}

	public static func step( _ job: Job, percent: Int, now: Date ) -> JobStep {
		switch job {

		case .charge( let n ):
			guard percent >= n else { return JobStep( job: job, intents: [], finished: false ) }
			// Below 100 hold at the reached level (v1 behaviour). At 100 there is nothing to hold: leave charging normal.
			let hold: Intent = n >= 100 ? .charging( on: true, holdAtLevel: nil ) : .charging( on: false, holdAtLevel: percent )
			return JobStep( job: job, intents: [ hold ], finished: true )

		case .discharge( let n ):
			guard percent <= n else { return JobStep( job: job, intents: [], finished: false ) }
			return JobStep( job: job, intents: [ .adapter( on: true ) ], finished: true )

		case .calibrate( var c ):
			guard c.advance( percent: percent, now: now ) else { return JobStep( job: .calibrate( c ), intents: [], finished: false ) }
			if c.phase == .done { return JobStep( job: .calibrate( c ), intents: charging, finished: true ) }
			return JobStep( job: .calibrate( c ), intents: intents( for: c.phase ), finished: false )
		}
	}

	private static let charging: [ Intent ] = [ .adapter( on: true ), .charging( on: true, holdAtLevel: nil ) ]

	private static func intents( for phase: Calibration.Phase ) -> [ Intent ] {
		switch phase {
		case .discharging15, .discharging80: return [ .adapter( on: false ) ]
		case .charging100, .holding: return charging
		case .done: return []
		}
	}

}
