import Foundation

/// Everything a client can ask the daemon, and the CLI's parsed form of it. Mirrors v1 commands; `visudo` /
/// `update_silent` are gone (no sudoers in v2). Codable: this is the XPC wire type, one JSON blob per call.
public enum Command: Codable, Equatable, Sendable {

	public enum Maintain: Codable, Equatable, Sendable {
		/// Remember a target. `enabled: false` stores it without holding (the app's slider while the limit switch is off).
		case set( MaintainTarget, forceDischarge: Bool, enabled: Bool )
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
	case schedule( days: Int )
	case charge( Int )
	case discharge( Int )
	case version
	case help
	case update
	case reinstall
	case uninstall

	/// Dev-only SMC key dump, not part of the v1 command set
	case probe
	/// Symlink /usr/local/bin/battery to the CLI inside /Applications/Battery.app (root-owned location only)
	case installCLI
	case uninstallCLI
	/// v1 (shell + sudoers + LaunchAgent) leftovers of the calling user
	case legacyFound
	case removeLegacy

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
		case "probe": self = .probe
		case "schedule":
			guard let setting, let n = Int( setting ), Limits.scheduleDays.contains( n ) else { throw BatteryError.missingArgument( "schedule DAYS[0-90, 0 = off]" ) }
			self = .schedule( days: n )
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
			self = .charge( try Self.percent( setting, in: Limits.chargeTargets ) )

		case "discharge":
			self = .discharge( try Self.percent( setting, in: Limits.dischargeTargets ) )

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
				self = .maintain( .set( try MaintainTarget( parsing: setting, hysteresis: hysteresis ), forceDischarge: force, enabled: true ) )
			}

		default:
			throw BatteryError.unknownCommand( action )
		}

	}

	/// Handled by the CLI itself, never sent to the daemon
	public var isLocal: Bool {
		switch self {
		case .help, .version, .logs, .update, .reinstall, .status, .statusCSV: return true
		default: return false
		}
	}

	// MARK: Wire form

	public func encoded() -> String {
		( try? JSONEncoder().encode( self ) ).flatMap { String( data: $0, encoding: .utf8 ) } ?? "{}"
	}

	public static func decode( _ json: String ) -> Command? {
		try? JSONDecoder().decode( Command.self, from: Data( json.utf8 ) )
	}

	private static func onOff( _ s: String? ) throws -> Bool {
		switch s {
		case "on": return true
		case "off": return false
		default: throw BatteryError.invalidOnOff( s ?? "" )
		}
	}

	private static func percent( _ s: String?, in range: ClosedRange<Int> ) throws -> Int {
		guard let s, let n = Int( s ), range.contains( n ) else { throw BatteryError.invalidPercentage( s ?? "" ) }
		return n
	}

}
