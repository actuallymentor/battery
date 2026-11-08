import Foundation
import BatteryCore

/// One-shot jobs: `charge N`, `discharge N`, `calibrate`. Maintenance pauses while one runs, then resumes.
final class Jobs {

	enum Kind {
		case charge( Int )
		case discharge( Int )
		case calibrate( Calibration )
	}

	private let smc: SMC
	private let caps: SMCCapabilities
	private let maintainer: Maintainer
	private var timer: Timer?
	private( set ) var kind: Kind?

	init( smc: SMC, caps: SMCCapabilities, maintainer: Maintainer ) {
		self.smc = smc
		self.caps = caps
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
		kind = nil
		maintainer.resume( restoring: restoring )
	}

	private func write( _ writes: [ SMCWrite ]? ) { writes?.forEach { smc.write( $0.key, hex: $0.hex ) } }

	/// Side effects for the phase a job just entered
	private func apply( _ k: Kind ) {
		switch k {
		case .charge: write( SMCPlan.adapter( on: true, caps ) ); write( SMCPlan.charging( true, caps ) )
		case .discharge: write( SMCPlan.adapter( on: false, caps ) )
		case .calibrate( let c ): applyPhase( c.phase )
		}
	}

	private func applyPhase( _ p: Calibration.Phase ) {
		switch p {
		case .discharging15, .discharging80: write( SMCPlan.adapter( on: false, caps ) )
		case .charging100, .holding: write( SMCPlan.adapter( on: true, caps ) ); write( SMCPlan.charging( true, caps ) )
		case .done: break
		}
	}

	private func tick() {
		guard let kind, let percent = Power.read()?.snapshot.percent else { return }

		switch kind {
		case .charge( let n ):
			if percent >= n { write( SMCPlan.charging( false, caps ) ); finish() }

		case .discharge( let n ):
			if percent <= n { write( SMCPlan.adapter( on: true, caps ) ); finish() }

		case .calibrate( var c ):
			if c.advance( percent: percent, now: Date() ) {
				self.kind = .calibrate( c )
				applyPhase( c.phase )
				if c.phase == .done { write( SMCPlan.adapter( on: true, caps ) ); write( SMCPlan.charging( true, caps ) ); finish() }
			} else {
				self.kind = .calibrate( c )   // holdStart lives inside the struct
			}
		}
	}

}
