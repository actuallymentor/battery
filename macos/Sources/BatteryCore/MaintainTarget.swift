import Foundation

/// Voltage bounds, mirrors v1 limits.
public enum Voltage {
	public static let range: ClosedRange<Double> = 10.5...12.6
	public static let hysteresisRange: ClosedRange<Double> = 0.1...2.0
	public static let defaultHysteresis = 0.1
}

/// What `battery maintain` keeps the battery at.
public enum MaintainTarget: Equatable, Sendable {

	/// Charge level band. A single value N is `lower == upper == N`.
	case level( lower: Int, upper: Int )

	/// Voltage band: center ± hysteresis.
	case voltage( center: Double, hysteresis: Double )

	/// "80", "70-80", "11.4V" (+ optional hysteresis "0.3V"). Nil for keywords like stop/recover.
	public init( parsing setting: String, hysteresis: String? = nil ) throws {

		// Voltage: "11.4V"
		if Self.isVoltage( setting ) {
			let center = Double( setting.dropLast() )!
			guard Voltage.range.contains( center ) else { throw BatteryError.invalidVoltage( setting ) }

			var hyst = Voltage.defaultHysteresis
			if let hysteresis {
				guard Self.isVoltage( hysteresis ), let parsed = Double( hysteresis.dropLast() ), Voltage.hysteresisRange.contains( parsed )
				else { throw BatteryError.invalidHysteresis( hysteresis ) }
				hyst = parsed
			}

			self = .voltage( center: center, hysteresis: hyst )
			return
		}

		// Range: "70-80", lower >= 10, upper <= 100, lower < upper
		if let dash = setting.firstIndex( of: "-" ) {
			let lower = Int( setting[ ..<dash ] ), upper = Int( setting[ setting.index( after: dash )... ] )
			guard let lower, let upper, lower >= 10, upper <= 100, lower < upper else { throw BatteryError.invalidMaintain( setting ) }
			self = .level( lower: lower, upper: upper )
			return
		}

		// Single value: "80"
		guard let level = Int( setting ), ( Limits.minMaintain...100 ).contains( level ) else { throw BatteryError.invalidMaintain( setting ) }
		self = .level( lower: level, upper: level )

	}

	private static func isVoltage( _ s: String ) -> Bool {
		s.hasSuffix( "V" ) && Double( s.dropLast() ) != nil && s.first?.isNumber == true
	}

	/// Persisted form, re-parseable by `init(persisted:)`. Same shape as v1 tracker files.
	public var persisted: String {
		switch self {
		case .level( let l, let u ): return l == u ? "\(l)" : "\(l)-\(u)"
		case .voltage( let c, let h ): return "\(Format.number( c ))V \(Format.number( h ))V"
		}
	}

	public init( persisted: String ) throws {
		let parts = persisted.split( separator: " " ).map( String.init )
		try self.init( parsing: parts.first ?? "", hysteresis: parts.count > 1 ? parts[ 1 ] : nil )
	}

	/// On-disk form in the daemon: the target plus an optional `--force-discharge` suffix.
	public func persistedLine( force: Bool ) -> String { persisted + ( force ? " --force-discharge" : "" ) }

	public static func parseLine( _ line: String ) -> ( target: MaintainTarget, force: Bool )? {
		let force = line.contains( "--force-discharge" )
		let setting = line.replacingOccurrences( of: " --force-discharge", with: "" ).trimmingCharacters( in: .whitespacesAndNewlines )
		return ( try? MaintainTarget( persisted: setting ) ).map { ( $0, force ) }
	}

	/// Human form: "80%", "70% - 80%", "11.4V ±0.1V"
	public var display: String {
		switch self {
		case .level( let l, let u ): return l == u ? "\(l)%" : "\(l)% - \(u)%"
		case .voltage( let c, let h ): return "\(Format.number( c ))V ±\(Format.number( h ))V"
		}
	}

}

enum Format {
	/// 11.4 -> "11.4", 12.0 -> "12"; avoids float noise like 11.399999
	static func number( _ v: Double ) -> String {
		let s = String( format: "%.3f", v )
		return s.replacingOccurrences( of: #"\.?0+$"#, with: "", options: .regularExpression )
	}
}
