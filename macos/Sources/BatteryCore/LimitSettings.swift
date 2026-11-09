import Foundation

/// What the popover edits: one limit. Charging resumes `band` points below it (v1's fixed 5 point hysteresis, ranges stay a CLI thing).
public struct LimitSettings: Equatable, Sendable {

	public static let sliderRange = 20...100
	public static let band = 5

	public private( set ) var limit: Int
	public var force: Bool

	public init( limit: Int = 80, force: Bool = true ) {
		self.limit = Self.sliderRange.clamp( limit )
		self.force = force
	}

	public mutating func setLimit( _ n: Int ) { limit = Self.sliderRange.clamp( n ) }

	/// The band to send: stop at the limit, resume `band` below (never under the maintain floor)
	public var target: MaintainTarget { .level( lower: max( limit - Self.band, Limits.minMaintain ), upper: limit ) }

	/// Adopt what the daemon is actually doing (CLI edits, reboot, other user). Only the upper edge: the band is ours.
	public mutating func adopt( _ t: MaintainTarget, force: Bool ) {
		guard case .level( _, let u ) = t else { return }
		setLimit( u )
		self.force = force
	}

	/// Where "Discharge to…" goes: ten points under the limit, never under the slider floor.
	public var dischargeTarget: Int { max( limit - 10, Self.sliderRange.lowerBound ) }

}
