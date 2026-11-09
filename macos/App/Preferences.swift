import Foundation
import SwiftUI
import BatteryCore

/// UserDefaults-backed settings. Keys live here so views and the model agree.
enum Pref {
	static let showPercent = "showPercentInMenuBar"
	static let appearance = "appearance"
	static let iconStyle = "menuBarIconStyle"
	static let limit = "chargeLimit"
	static let forceDischarge = "forceDischarge"
	static let lowBatteryAlert = "lowBatteryAlert"
	static let lowBatteryLevel = "lowBatteryLevel"
	static let legacyDeclined = "legacyCleanupDeclined"
	static let onboarded = "onboarded"
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
	var scheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
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
			Pref.limit: 80,
			Pref.forceDischarge: true,
			Pref.lowBatteryAlert: true,
			Pref.lowBatteryLevel: 15,
		] )
	}
}

extension LimitSettings {

	/// Edits survive restarts (the daemon's target still wins on contact, see AppModel.adoptOutsideChanges).
	static func load() -> LimitSettings {
		UserDefaults.registerBatteryDefaults()
		let d = UserDefaults.standard
		return LimitSettings( limit: d.integer( forKey: Pref.limit ), force: d.bool( forKey: Pref.forceDischarge ) )
	}

	func save() {
		let d = UserDefaults.standard
		d.set( limit, forKey: Pref.limit )
		d.set( force, forKey: Pref.forceDischarge )
	}

}
