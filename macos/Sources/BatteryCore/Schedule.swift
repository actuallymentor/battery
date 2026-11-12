import Foundation

/// "Top off to 100% every N days" (#450). Pure: the daemon feeds it the clock and acts on `isDue`.
public struct Schedule: Equatable, Sendable {

	public private( set ) var days: Int
	public private( set ) var lastRun: Date?

	public init( days: Int = 0, lastRun: Date? = nil ) {
		self.days = Limits.scheduleDays.clamp( days )
		self.lastRun = lastRun
	}

	/// Turning it on counts from `now`, never from a stale last run.
	public mutating func set( days: Int, now: Date ) {
		let wasOff = self.days == 0
		self.days = Limits.scheduleDays.clamp( days )
		if self.days > 0, wasOff || lastRun == nil { lastRun = now }
	}

	public var nextRun: Date? {
		guard days > 0, let lastRun else { return nil }
		return lastRun.addingTimeInterval( Double( days ) * 86400 )
	}

	/// Due, plugged in and nothing else running.
	public func isDue( now: Date, acAttached: Bool, busy: Bool ) -> Bool {
		guard let next = nextRun else { return false }
		return now >= next && acAttached && !busy
	}

	public mutating func markRun( now: Date ) { lastRun = now }

	// MARK: Persistence ( "30 1794176743.5" )

	public var persisted: String { "\( days ) \( lastRun?.timeIntervalSince1970 ?? 0 )" }

	public init( persisted: String ) {
		let parts = persisted.split( separator: " " )
		let days = parts.first.flatMap { Int( $0 ) } ?? 0
		let last = parts.count > 1 ? Double( parts[ 1 ] ).flatMap { $0 > 0 ? Date( timeIntervalSince1970: $0 ) : nil } : nil
		self.init( days: days, lastRun: last )
	}

}

extension ClosedRange where Bound == Int {
	public func clamp( _ v: Int ) -> Int { Swift.min( Swift.max( v, lowerBound ), upperBound ) }
}
