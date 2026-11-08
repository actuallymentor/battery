import Foundation

/// What the popover edits: a limit, an optional lower bound, presets. All clamping lives here so the views stay thin.
public struct LimitSettings: Equatable, Sendable {

	public static let defaultPresets = [ 60, 70, 80, 90 ]
	public static let maxPresets = 6
	public static let sliderRange = 20...100

	public private( set ) var limit: Int
	public private( set ) var lower: Int
	public var force: Bool
	public private( set ) var presets: [ Int ]

	public init( limit: Int = 80, lower: Int = 75, force: Bool = false, presets: [ Int ] = LimitSettings.defaultPresets ) {
		self.limit = Self.sliderRange.clamp( limit )
		self.lower = Self.clampLower( lower, limit: self.limit )
		self.force = force
		self.presets = Self.clean( presets )
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

	// MARK: Presets

	public mutating func addPreset( _ n: Int ) { presets = Self.clean( presets + [ n ] ) }
	public mutating func removePreset( _ n: Int ) { presets = presets.filter { $0 != n } }
	public mutating func resetPresets() { presets = Self.defaultPresets }

	private static func clean( _ raw: [ Int ] ) -> [ Int ] {
		Array( Set( raw.filter { sliderRange.contains( $0 ) } ).sorted().prefix( maxPresets ) )
	}

	/// UserDefaults string form: "60,70,80"
	public var presetsString: String { presets.map( String.init ).joined( separator: "," ) }
	public static func presets( from string: String ) -> [ Int ] { string.split( separator: "," ).compactMap { Int( $0 ) } }

}
