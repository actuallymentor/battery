import Foundation
import IOKit
import BatteryCore

/// Battery readings from AppleSmartBattery (no shelling out to pmset/ioreg).
enum Power {

	private static func properties() -> [ String: Any ]? {
		let service = IOServiceGetMatchingService( kIOMainPortDefault, IOServiceMatching( "AppleSmartBattery" ) )
		guard service != 0 else { return nil }
		defer { IOObjectRelease( service ) }
		var dict: Unmanaged<CFMutableDictionary>?
		guard IORegistryEntryCreateCFProperties( service, &dict, kCFAllocatorDefault, 0 ) == kIOReturnSuccess else { return nil }
		return dict?.takeRetainedValue() as? [ String: Any ]
	}

	/// Percent, AC attached, minutes to empty/full ( nil = no estimate ), pack voltage in V.
	static func read() -> ( snapshot: PowerSnapshot, voltage: Double? )? {
		guard let p = properties(), let percent = p[ "CurrentCapacity" ] as? Int else { return nil }
		let ac = p[ "ExternalConnected" ] as? Bool ?? false
		let minutes = p[ "TimeRemaining" ] as? Int
		let remaining = minutes.map { $0 >= 0 && $0 < 6000 ? "\( $0 / 60 ):\( String( format: "%02d", $0 % 60 ) )" : "no estimate" } ?? "no estimate"
		let voltage = ( p[ "Voltage" ] as? Int ).map { Double( $0 ) / 1000 }
		return ( PowerSnapshot( percent: percent, remaining: remaining, acAttached: ac ), voltage )
	}

}
