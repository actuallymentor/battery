import Foundation

/// Bounds enforced by BatteryCore parsers AND the root daemon: a client (CLI, app, anything that passes the
/// XPC signature check) must not be able to ask for something that drains the Mac to shutdown.
public enum Limits {

	/// Lowest level `maintain` may hold (matches the range lower bound)
	public static let minMaintain = 10

	/// Lowest level a `discharge` job may run to
	public static let minDischarge = 5

	public static let chargeTargets = 1...100
	public static let dischargeTargets = minDischarge...100
	public static let scheduleDays = 0...90

	/// Why the daemon refuses a command on this Mac, nil when fine. The one gate every command passes: ranges and capabilities.
	public static func refusal( _ cmd: Command, caps: SMCCapabilities ) -> String? {
		switch cmd {
		case .charge( let n ): return check( charge: n ) ?? chargeControl( caps )
		case .charging: return chargeControl( caps )
		case .discharge( let n ): return check( discharge: n ) ?? ( caps.canCutAdapter ? nil : "Discharging isn't available on this Mac (no adapter-cut key)." )
		case .adapter: return caps.canCutAdapter ? nil : "No adapter-cut key on this Mac."
		case .calibrate: return caps.canCutAdapter && caps.backend != .none ? nil : "Calibration isn't available on this Mac (needs adapter cut and charge control)."
		case .schedule( let days ): return scheduleDays.contains( days ) ? nil : "Schedule must be 0-90 days."
		case .maintain( .set( let t, let force, _ ) ): return check( maintain: t, force: force, caps: caps )
		default: return nil
		}
	}

	public static func check( charge n: Int ) -> String? {
		chargeTargets.contains( n ) ? nil : "Charge target must be \( chargeTargets.lowerBound )-\( chargeTargets.upperBound )%."
	}

	public static func check( discharge n: Int ) -> String? {
		dischargeTargets.contains( n ) ? nil : "Discharge target must be \( minDischarge )-100% (lower would run the battery flat)."
	}

	public static func check( maintain t: MaintainTarget ) -> String? {
		switch t {
		case .level( let lower, let upper ):
			guard lower >= minMaintain, upper <= 100, lower <= upper else { return "Maintain level must be \( minMaintain )-100%." }
		case .voltage( let center, let hysteresis ):
			guard Voltage.range.contains( center ), Voltage.hysteresisRange.contains( hysteresis ) else { return "Voltage target out of range." }
		}
		return nil
	}

	/// Whether this Mac can hold `t` at all.
	public static func check( maintain t: MaintainTarget, force: Bool, caps: SMCCapabilities ) -> String? {
		if let why = check( maintain: t ) ?? chargeControl( caps ) { return why }
		if caps.backend == .firmwareLimit {
			if case .voltage = t { return "Voltage targets aren't available on this Mac (firmware limit). Use a percentage." }
			if case .level( _, let upper ) = t, upper < SMCPlan.firmwareFloor { return "This Mac's firmware can't hold below \( SMCPlan.firmwareFloor )%." }
		}
		if force, !caps.canCutAdapter { return "Force discharge isn't available on this Mac (no adapter-cut key)." }
		return nil
	}

	/// The one message for "no way to hold charging here", also shown as the status warning
	public static func chargeControl( _ caps: SMCCapabilities ) -> String? {
		caps.backend == .none ? "This Mac exposes no charge-limit control (looked for CHTE, CH0B/CH0C, bfD0/bfE0/bfF0, CHIE). Found: \( caps.keys.sorted().joined( separator: " " ) )." : nil
	}

}
