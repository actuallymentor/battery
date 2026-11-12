import Foundation

/// The app's one-number view of a maintain target: a limit, held as a band `band` points wide (v1's fixed 5 point
/// hysteresis, ranges stay a CLI thing). The daemon remembers the target; this only converts slider <-> band.
public enum LimitSettings {

	public static let sliderRange = 20...100
	public static let band = 5
	public static let defaultLimit = 80

	/// The band to send: stop at the limit, resume `band` below (never under the maintain floor)
	public static func target( limit: Int ) -> MaintainTarget {
		let limit = sliderRange.clamp( limit )
		return .level( lower: max( limit - band, Limits.minMaintain ), upper: limit )
	}

	/// What the slider shows for a daemon target: the top of the band, the default for voltage targets or none yet
	public static func limit( of t: MaintainTarget? ) -> Int { t?.upper.map( sliderRange.clamp ) ?? defaultLimit }

	/// Where "Discharge to…" goes: ten points under the limit, never under the slider floor.
	public static func dischargeTarget( limit: Int ) -> Int { max( limit - 10, sliderRange.lowerBound ) }

}
