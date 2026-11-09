import Foundation

/// What the popover edits: a limit and an optional lower bound. All clamping lives here so the views stay thin.
public struct LimitSettings: Equatable, Sendable {

	public static let sliderRange = 20...100

	public private( set ) var limit: Int
	public private( set ) var lower: Int
	public var force: Bool

	public init( limit: Int = 80, lower: Int = 75, force: Bool = false ) {
		self.limit = Self.sliderRange.clamp( limit )
		self.lower = Self.clampLower( lower, limit: self.limit )
		self.force = force
	}

	public mutating func setLimit( _ n: Int ) {
		limit = Self.sliderRange.clamp( n )
		lower = Self.clampLower( lower, limit: limit )
	}

	/// Resume-below: never above the limit, never below the maintain floor.
	public mutating func setLower( _ n: Int ) { lower = Self.clampLower( n, limit: limit ) }

	private static func clampLower( _ n: Int, limit: Int ) -> Int { ( Limits.minMaintain...limit ).clamp( n ) }

	/// The band to send. A lower bound equal to the limit means a plain single level.
	public var target: MaintainTarget { lower < limit ? .level( lower: lower, upper: limit ) : .level( lower: limit, upper: limit ) }

	/// Adopt what the daemon is actually doing (CLI edits, reboot, other user).
	public mutating func adopt( _ t: MaintainTarget, force: Bool ) {
		guard case .level( let l, let u ) = t else { return }
		setLimit( u )
		setLower( l )
		self.force = force
	}

	/// Where "Discharge to…" goes: ten points under the limit, never under the slider floor.
	public var dischargeTarget: Int { max( limit - 10, Self.sliderRange.lowerBound ) }

}
