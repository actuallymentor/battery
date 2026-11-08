import Foundation

/// Parsed CLI invocation. Mirrors v1 commands; `visudo` / `update_silent` are gone (no sudoers in v2).
public enum Command: Equatable, Sendable {

	public enum Maintain: Equatable, Sendable {
		case set( MaintainTarget, forceDischarge: Bool )
		case stop
		case recover
	}

	case status
	case statusCSV
	case logs( lines: Int )
	case maintain( Maintain )
	case charging( on: Bool )
	case adapter( on: Bool )
	case calibrate
	case charge( Int )
	case discharge( Int )
	case version
	case help
	case update
	case reinstall
	case uninstall

	/// `args` excludes the program name.
	public init( arguments args: [ String ] ) throws {

		guard let action = args.first else { self = .help; return }
		let setting = args.count > 1 ? args[ 1 ] : nil

		switch action {

		case "help", "--help", "-h": self = .help
		case "version", "--version": self = .version
		case "status": self = .status
		case "status_csv": self = .statusCSV
		case "calibrate": self = .calibrate
		case "update": self = .update
		case "reinstall": self = .reinstall
		case "uninstall": self = .uninstall

		case "logs":
			self = .logs( lines: setting.flatMap( Int.init ) ?? 100 )

		case "charging":
			self = .charging( on: try Self.onOff( setting ) )

		case "adapter":
			self = .adapter( on: try Self.onOff( setting ) )

		case "charge":
			self = .charge( try Self.percent( setting ) )

		case "discharge":
			self = .discharge( try Self.percent( setting ) )

		case "maintain":
			guard let setting else { throw BatteryError.missingArgument( "maintain PERCENTAGE|RANGE|VOLTAGE|stop" ) }
			switch setting {
			case "stop": self = .maintain( .stop )
			case "recover": self = .maintain( .recover )
			default:
				// `--force-discharge` may sit in either trailing slot (voltage takes a hysteresis first)
				let rest = Array( args.dropFirst( 2 ) )
				let force = rest.contains( "--force-discharge" )
				let hysteresis = rest.first { $0 != "--force-discharge" }
				self = .maintain( .set( try MaintainTarget( parsing: setting, hysteresis: hysteresis ), forceDischarge: force ) )
			}

		default:
			throw BatteryError.unknownCommand( action )
		}

	}

	private static func onOff( _ s: String? ) throws -> Bool {
		switch s {
		case "on": return true
		case "off": return false
		default: throw BatteryError.invalidOnOff( s ?? "" )
		}
	}

	private static func percent( _ s: String? ) throws -> Int {
		guard let s, let n = Int( s ), ( 0...100 ).contains( n ) else { throw BatteryError.invalidPercentage( s ?? "" ) }
		return n
	}

}
