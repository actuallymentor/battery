import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import BatteryCore

/// Battery readings from AppleSmartBattery (no shelling out to pmset/ioreg) and power events.
enum Power {

	struct Reading {
		var snapshot: PowerSnapshot
		var voltage: Double?
		var isCharging: Bool?
		var amperage: Int?          // mA, + into the pack
		var cycleCount: Int?
		var healthPercent: Int?
	}

	private static func properties() -> [ String: Any ]? {
		let service = IOServiceGetMatchingService( kIOMainPortDefault, IOServiceMatching( "AppleSmartBattery" ) )
		guard service != 0 else { return nil }
		defer { IOObjectRelease( service ) }
		var dict: Unmanaged<CFMutableDictionary>?
		guard IORegistryEntryCreateCFProperties( service, &dict, kCFAllocatorDefault, 0 ) == kIOReturnSuccess else { return nil }
		return dict?.takeRetainedValue() as? [ String: Any ]
	}

	static func read() -> Reading? {
		guard let p = properties(), let percent = ( p[ "CurrentCapacity" ] as? NSNumber )?.intValue else { return nil }
		let ac = ( p[ "ExternalConnected" ] as? NSNumber )?.boolValue ?? false
		let minutes = ( p[ "TimeRemaining" ] as? NSNumber )?.intValue
		let remaining = minutes.map { $0 >= 0 && $0 < 6000 ? "\( $0 / 60 ):\( String( format: "%02d", $0 % 60 ) )" : "no estimate" } ?? "no estimate"

		// Amperage is a signed value the registry stores as unsigned: int64Value wraps it back
		let amps = ( p[ "Amperage" ] as? NSNumber ).map { Int( $0.int64Value ) }
		let design = ( p[ "DesignCapacity" ] as? NSNumber )?.intValue
		let rawMax = ( p[ "AppleRawMaxCapacity" ] as? NSNumber )?.intValue
		let health = ( design != nil && rawMax != nil && design! > 0 ) ? min( 100, rawMax! * 100 / design! ) : nil

		return Reading(
			snapshot: PowerSnapshot( percent: percent, remaining: remaining, acAttached: ac ),
			voltage: ( p[ "Voltage" ] as? NSNumber ).map { $0.doubleValue / 1000 },
			isCharging: ( p[ "IsCharging" ] as? NSNumber )?.boolValue,
			amperage: amps,
			cycleCount: ( p[ "CycleCount" ] as? NSNumber )?.intValue,
			healthPercent: health )
	}

}

/// Wake / sleep and plug / unplug notifications, so the control loop reacts at once instead of on its next tick.
final class PowerEvents {

	var onWake: () -> Void = {}
	var onWillSleep: () -> Void = {}
	var onSourceChange: () -> Void = {}

	private var root: io_connect_t = 0
	private var notifier: io_object_t = 0

	func start() {

		// Sleep / wake
		var port: IONotificationPortRef?
		root = IORegisterForSystemPower( Unmanaged.passUnretained( self ).toOpaque(), &port, { refcon, _, type, arg in
			let me = Unmanaged<PowerEvents>.fromOpaque( refcon! ).takeUnretainedValue()
			switch type {
			case 0xe0000280:   // kIOMessageSystemWillSleep
				me.onWillSleep()
				IOAllowPowerChange( me.root, Int( bitPattern: arg ) )
			case 0xe0000270:   // kIOMessageCanSystemSleep
				IOAllowPowerChange( me.root, Int( bitPattern: arg ) )
			case 0xe0000300:   // kIOMessageSystemHasPoweredOn
				me.onWake()
			default: break
			}
		}, &notifier )
		if let port { CFRunLoopAddSource( CFRunLoopGetMain(), IONotificationPortGetRunLoopSource( port ).takeUnretainedValue(), .commonModes ) }

		// Power source (plug / unplug, % change)
		let src = IOPSNotificationCreateRunLoopSource( { ctx in
			Unmanaged<PowerEvents>.fromOpaque( ctx! ).takeUnretainedValue().onSourceChange()
		}, Unmanaged.passUnretained( self ).toOpaque() )?.takeRetainedValue()
		if let src { CFRunLoopAddSource( CFRunLoopGetMain(), src, .commonModes ) }
	}

}
