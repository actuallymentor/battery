import Foundation
import BatteryCore

/// One-shot jobs: `charge N`, `discharge N`, `calibrate`. Maintenance pauses while one runs, then resumes.
final class Jobs {

	enum Kind {
		case charge( Int )
		case discharge( Int )
		case calibrate( Calibration )
	}

	private let control: ChargeControl
	private let maintainer: Maintainer
	private var timer: Timer?
	private( set ) var kind: Kind?

	init( control: ChargeControl, maintainer: Maintainer ) {
		self.control = control
		self.maintainer = maintainer
	}

	/// Human line for `status`, nil when idle.
	var activity: String? {
		switch kind {
		case .charge( let n ): return "Charging to \( n )%"
		case .discharge( let n ): return "Discharging to \( n )%"
		case .calibrate( let c ): return "Calibrating: \( c.phase.message )"
		case nil: return nil
		}
	}

	func start( _ k: Kind ) {
		cancel()
		maintainer.suspend()
		kind = k
		log( "job start: \( activity ?? "" )" )
		apply( k )
		timer = Timer.scheduledTimer( withTimeInterval: 20, repeats: true ) { [ weak self ] _ in self?.tick() }
		tick()
	}

	/// Abort: back to normal charging
	func cancel() { end( restoring: true ) }

	/// Job reached its goal: keep what it set (e.g. charging held off after `charge N`)
	private func finish() { end( restoring: false ) }

	private func end( restoring: Bool ) {
		timer?.invalidate(); timer = nil
		guard kind != nil else { return }
		log( "job end (\( restoring ? "cancelled" : "done" ))" )
		kind = nil
		maintainer.resume( restoring: restoring )
	}

	/// Side effects for the phase a job just entered
	private func apply( _ k: Kind ) {
		switch k {
		case .charge: control.adapter( on: true ); control.charging( true )
		case .discharge: control.adapter( on: false )
		case .calibrate( let c ): applyPhase( c.phase )
		}
	}

	private func applyPhase( _ p: Calibration.Phase ) {
		switch p {
		case .discharging15, .discharging80: control.adapter( on: false )
		case .charging100, .holding: control.adapter( on: true ); control.charging( true )
		case .done: break
		}
	}

	private func tick() {
		guard let kind, let percent = Power.read()?.snapshot.percent else { return }

		switch kind {
		case .charge( let n ):
			if percent >= n { control.charging( false, level: percent ); finish() }

		case .discharge( let n ):
			if percent <= n { control.adapter( on: true ); finish() }

		case .calibrate( var c ):
			if c.advance( percent: percent, now: Date() ) {
				self.kind = .calibrate( c )
				log( "calibrate: \( c.phase.message )" )
				applyPhase( c.phase )
				if c.phase == .done { control.adapter( on: true ); control.charging( true ); finish() }
			} else {
				self.kind = .calibrate( c )   // holdStart lives inside the struct
			}
		}
	}

}
