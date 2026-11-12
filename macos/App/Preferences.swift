import Foundation
import SwiftUI
import BatteryCore

/// UserDefaults-backed settings: the app's own looks and alerts. The charge limit is not here, the daemon remembers it.
enum Pref {
	static let showPercent = "showPercentInMenuBar"
	static let appearance = "appearance"
	static let iconStyle = "menuBarIconStyle"
	static let lowBatteryAlert = "lowBatteryAlert"
	static let lowBatteryLevel = "lowBatteryLevel"
	static let legacyDeclined = "legacyCleanupDeclined"
	static let loginItemDefaulted = "loginItemDefaulted"
}

enum IconStyle: String, CaseIterable, Identifiable {
	case battery, bolt, shield
	var id: String { rawValue }
	var title: String { switch self { case .battery: return "Battery"; case .bolt: return "Bolt"; case .shield: return "Shield" } }
}

/// Follows the device theme unless the user picks one
enum Appearance: String, CaseIterable, Identifiable {
	case system, light, dark
	var id: String { rawValue }
	var title: String { rawValue.capitalized }
	/// Menu bar popover and Settings are separate windows: set it app-wide
	var nsAppearance: NSAppearance? { switch self { case .system: return nil; case .light: return NSAppearance( named: .aqua ); case .dark: return NSAppearance( named: .darkAqua ) } }
}

extension UserDefaults {
	/// Registered once at launch so `@AppStorage` defaults and manual reads agree.
	static func registerBatteryDefaults() {
		standard.register( defaults: [
			Pref.showPercent: true,
			Pref.appearance: Appearance.system.rawValue,
			Pref.iconStyle: IconStyle.battery.rawValue,
			Pref.lowBatteryAlert: true,
			Pref.lowBatteryLevel: 15,
		] )
	}
}
