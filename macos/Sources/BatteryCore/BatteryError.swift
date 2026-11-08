import Foundation

/// User-facing errors. `description` is what the CLI prints.
public enum BatteryError: Error, Equatable, CustomStringConvertible {

	case invalidPercentage( String )
	case invalidMaintain( String )
	case invalidVoltage( String )
	case invalidHysteresis( String )
	case invalidOnOff( String )
	case unknownCommand( String )
	case missingArgument( String )
	case unsupportedHardware( String )
	case notAuthorized( String )
	case daemonUnavailable( String )

	public var description: String {
		switch self {
		case .invalidPercentage( let v ): return "\(v) is not a valid percentage. Use a number between 0 and 100"
		case .invalidMaintain( let v ): return "\(v) is not a valid setting for battery maintain. Use a number between 0 and 100, a range like 70-80, a voltage like 11.4V, or 'stop' / 'recover'"
		case .invalidVoltage( let v ): return "\(v) is not a valid voltage. Use a value between \(Voltage.range.lowerBound)V and \(Voltage.range.upperBound)V"
		case .invalidHysteresis( let v ): return "\(v) is not a valid hysteresis. Use a value between \(Voltage.hysteresisRange.lowerBound)V and \(Voltage.hysteresisRange.upperBound)V"
		case .invalidOnOff( let v ): return "\(v) is not \"on\" or \"off\""
		case .unknownCommand( let v ): return "Unknown command '\(v)'. Run 'battery help'"
		case .missingArgument( let v ): return "Missing argument: \(v)"
		case .unsupportedHardware( let v ): return "Unsupported hardware: \(v)"
		case .notAuthorized( let v ): return "Not authorized: \(v)"
		case .daemonUnavailable( let v ): return "Battery daemon unavailable: \(v)"
		}
	}

}
