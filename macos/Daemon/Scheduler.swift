import Foundation
import BatteryCore

/// "Top off to 100% every N days" (#450). Persisted, checked hourly and on wake, so a missed run (Mac asleep or off)
/// happens as soon as the Mac is back on AC. The rules live in `Schedule` (pure, tested). Main-queue only.
final class Scheduler {

	private let file = URL( fileURLWithPath: batteryStateDir + "/schedule" )
	private let jobs: Jobs
	private var timer: Timer?
	private var schedule: Schedule

	init( jobs: Jobs ) {
		self.jobs = jobs
		schedule = ( try? String( contentsOf: file, encoding: .utf8 ) ).map { Schedule( persisted: $0 ) } ?? Schedule()
		timer = Timer.scheduledTimer( withTimeInterval: 3600, repeats: true ) { [ weak self ] _ in self?.check() }
	}

	var days: Int { schedule.days }
	var nextRun: Date? { schedule.nextRun }

	func set( days: Int ) {
		schedule.set( days: days, now: Date() )
		save()
		log( "schedule: top off every \( schedule.days ) days" )
	}

	func check() {
		let ac = Power.read()?.snapshot.acAttached ?? false
		guard schedule.isDue( now: Date(), acAttached: ac, busy: jobs.job != nil ) else { return }
		log( "schedule: top-off due, charging to 100%" )
		schedule.markRun( now: Date() )
		save()
		jobs.start( .charge( 100 ) )
	}

	private func save() {
		try? FileManager.default.createDirectory( at: file.deletingLastPathComponent(), withIntermediateDirectories: true )
		try? schedule.persisted.write( to: file, atomically: true, encoding: .utf8 )
	}

}
