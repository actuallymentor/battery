import Foundation
import BatteryCore

/// "Charge to 100% every N days" (#450): resets the gauge and fights lithium-ion drift without leaving the pack full.
/// Persisted, checked hourly and on wake, so a missed run (Mac asleep or off) happens as soon as the Mac is back on AC.
final class Scheduler {

	private let file = URL( fileURLWithPath: "/var/db/co.palokaj.battery/schedule" )
	private let jobs: Jobs
	private var timer: Timer?

	/// Days between top-offs, 0 = off
	private( set ) var days = 0
	private( set ) var lastRun: Date?

	init( jobs: Jobs ) {
		self.jobs = jobs
		load()
		timer = Timer.scheduledTimer( withTimeInterval: 3600, repeats: true ) { [ weak self ] _ in self?.check() }
	}

	var nextRun: Date? {
		guard days > 0 else { return nil }
		return ( lastRun ?? Date() ).addingTimeInterval( Double( days ) * 86400 )
	}

	func set( days: Int ) {
		let wasOff = self.days == 0
		self.days = max( 0, min( days, 90 ) )
		// Turning it on counts from now, never from a stale last run
		if self.days > 0, wasOff || lastRun == nil { lastRun = Date() }
		save()
		log( "schedule: top off every \( self.days ) days" )
	}

	/// Due and plugged in, no other job running: run it.
	func check() {
		guard days > 0, jobs.kind == nil, let next = nextRun, Date() >= next, Power.read()?.snapshot.acAttached == true else { return }
		log( "schedule: top-off due, charging to 100%" )
		lastRun = Date()
		save()
		jobs.start( .charge( 100 ) )
	}

	private func load() {
		guard let raw = try? String( contentsOf: file, encoding: .utf8 ) else { return }
		let parts = raw.split( separator: " " )
		days = parts.first.flatMap { Int( $0 ) } ?? 0
		lastRun = parts.count > 1 ? Double( parts[ 1 ] ).map { Date( timeIntervalSince1970: $0 ) } : nil
	}

	private func save() {
		try? FileManager.default.createDirectory( at: file.deletingLastPathComponent(), withIntermediateDirectories: true )
		try? "\( days ) \( lastRun?.timeIntervalSince1970 ?? 0 )".write( to: file, atomically: true, encoding: .utf8 )
	}

}
