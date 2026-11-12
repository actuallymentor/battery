import Foundation
import BatteryCore

/// Runs one-shot jobs (`charge N`, `discharge N`, `calibrate`) on a timer. The rules live in `JobPlanner`
/// (pure, tested); this only hands intents to `ChargeControl`. Maintenance pauses while a job runs, then resumes.
/// Main-queue only.
final class Jobs {

	private let control: ChargeControl
	private let maintainer: Maintainer
	private var timer: Timer?
	private( set ) var job: Job?

	init( control: ChargeControl, maintainer: Maintainer ) {
		self.control = control
		self.maintainer = maintainer
	}

	/// Line for `status`, nil when idle.
	var activity: String? { job?.activity }

	func start( _ j: Job ) {
		abort()
		maintainer.suspend()
		job = j
		log( "job start: \( j.activity )" )
		run( JobPlanner.start( j ) )
		timer = Timer.scheduledTimer( withTimeInterval: 20, repeats: true ) { [ weak self ] _ in self?.tick() }
		tick()
	}

	/// User cancel: back to normal charging (or the maintain target).
	func cancel() { end( restoring: true ) }

	/// Replaced by a new owner of the hardware (a new maintain target, a manual override): no hardware writes, no resume.
	func abort() {
		timer?.invalidate(); timer = nil
		guard job != nil else { return }
		log( "job replaced" )
		job = nil
		maintainer.release()
	}

	/// After wake the adapter was restored for sleep: put the job's state back.
	func reconcile() { if let job { run( JobPlanner.start( job ) ) } }

	private func end( restoring: Bool ) {
		timer?.invalidate(); timer = nil
		guard job != nil else { return }
		log( "job end (\( restoring ? "cancelled" : "done" ))" )
		job = nil
		maintainer.resume( restoring: restoring )
	}

	private func tick() {
		guard let current = job, let percent = Power.read()?.snapshot.percent else { return }
		let step = JobPlanner.step( current, percent: percent, now: Date() )

		job = step.job
		if case .calibrate( let before ) = current, case .calibrate( let after ) = step.job, before.phase != after.phase { log( "calibrate: \( after.phase.message )" ) }

		run( step.intents )
		if step.finished { end( restoring: false ) }
	}

	private func run( _ intents: [ Intent ] ) { control.run( intents ) }

}
