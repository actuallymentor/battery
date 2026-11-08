import Foundation

/// Parsed `pmset -g batt`.
public struct PowerSnapshot: Equatable, Sendable {
	public var percent: Int
	public var remaining: String   // "1:23", "0:00", "(no estimate)" -> "no estimate"
	public var acAttached: Bool

	public init( percent: Int, remaining: String, acAttached: Bool ) {
		self.percent = percent
		self.remaining = remaining
		self.acAttached = acAttached
	}

	/// Input sample:
	/// ```
	/// Now drawing from 'AC Power'
	///  -InternalBattery-0 (id=23855203)	100%; charged; 0:00 remaining present: true
	/// ```
	public init?( pmset output: String ) {
		let lines = output.split( separator: "\n" ).map( String.init )
		guard let first = lines.first, let batt = lines.first( where: { $0.contains( "InternalBattery" ) } ),
			  let match = batt.range( of: #"(\d+)%"#, options: .regularExpression )
		else { return nil }

		percent = Int( batt[ match ].dropLast() )!
		acAttached = first.contains( "AC Power" )

		// "...; 1:23 remaining present" or "(no estimate) present"
		if let t = batt.range( of: #"\d+:\d+ remaining"#, options: .regularExpression ) {
			remaining = String( batt[ t ].dropLast( " remaining".count ) )
		} else {
			remaining = "no estimate"
		}
	}
}

public enum Report {

	/// `battery status`
	public static func status( _ p: PowerSnapshot, voltage: Double?, charging: Bool?, maintain: MaintainTarget? ) -> String {
		var out = "Battery at \(p.percent)% (\(p.remaining) remaining), \(voltage.map( Format.number ) ?? "?")V, smc charging \(word( charging ))"
		if let maintain { out += "\nYour battery is currently being maintained at \(maintain.display)" }
		return out
	}

	/// `battery status`, rendered from the daemon snapshot so the root daemon never formats text
	public static func status( _ s: BatteryStatus ) -> String {
		var out = status( PowerSnapshot( percent: s.percent, remaining: s.remaining, acAttached: s.acAttached ), voltage: s.voltage, charging: s.chargingEnabled, maintain: s.maintainTarget )
		if let activity = s.activity { out += "\n\( activity )" }
		if let warning = s.warning { out += "\nWarning: \( warning )" }
		return out
	}

	public static func csv( _ s: BatteryStatus ) -> String {
		csv( PowerSnapshot( percent: s.percent, remaining: s.remaining, acAttached: s.acAttached ), charging: s.chargingEnabled, discharging: s.discharging, maintain: s.maintainTarget )
	}

	/// `battery status_csv`: percent,remaining,charging,discharging,maintain
	public static func csv( _ p: PowerSnapshot, charging: Bool?, discharging: Bool?, maintain: MaintainTarget? ) -> String {
		let d = discharging.map { $0 ? "discharging" : "not discharging" } ?? "unknown"
		return [ String( p.percent ), p.remaining, word( charging ), d, maintain?.persisted ?? "" ].joined( separator: "," )
	}

	private static func word( _ enabled: Bool? ) -> String {
		enabled.map { $0 ? "enabled" : "disabled" } ?? "unknown"
	}

	public static let help = """
	Battery CLI utility

	Usage:

	  battery status
	    output battery SMC status, % and time remaining

	  battery logs LINES[integer, optional]
	    output logs of the battery CLI and GUI
	    eg: battery logs 100

	  battery maintain PERCENTAGE[0-100,stop] or RANGE[lower-upper]
	    reboot-persistent battery level maintenance: turn off charging above, and on below a certain value
	    it has the option of a --force-discharge flag that discharges even when plugged in (this does NOT work well with clamshell mode)
	    eg: battery maintain 80           # maintain at 80%
	    eg: battery maintain 70-80        # maintain between 70-80%
	    eg: battery maintain stop

	  battery maintain VOLTAGE[10.5V-12.6V,stop] (HYSTERESIS[0.1V-2V])
	    reboot-persistent battery level maintenance: keep battery at a certain voltage
	  default hysteresis: 0.1V
	    eg: battery maintain 11.4V       # keeps battery between 11.3V and 11.5V
	    eg: battery maintain 11.4V 0.3V  # keeps battery between 11.1V and 11.7V

	  battery charging SETTING[on/off]
	    manually set the battery to (not) charge
	    eg: battery charging on

	  battery adapter SETTING[on/off]
	    manually set the adapter to (not) charge even when plugged in
	    eg: battery adapter off

	  battery schedule DAYS[0-90]
	    top off to 100% every DAYS days (0 turns it off), runs when plugged in
	    eg: battery schedule 30

	  battery calibrate
	    calibrate the battery by discharging it to 15%, then recharging it to 100%, and keeping it there for 1 hour
	    battery maintenance is restored upon completion
	    menubar battery app execution and/or battery maintain command will interrupt calibration

	  battery charge LEVEL[0-100]
	    charge the battery to a certain percentage; battery maintenance is restored upon completion
	    eg: battery charge 90

	  battery discharge LEVEL[0-100]
	    block adapter power until the battery reaches the specified level; battery maintenance is restored upon completion
	    eg: battery discharge 90

	  battery update
	    check for a newer version of the Battery app

	  battery uninstall
	    enable charging, unregister the daemon and remove Battery
	"""

}
