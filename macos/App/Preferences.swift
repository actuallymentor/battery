import Foundation
import SwiftUI

/// UserDefaults-backed settings. Keys live here so views and the model agree.
enum Pref {
	static let showPercent = "showPercentInMenuBar"
	static let iconStyle = "menuBarIconStyle"
	static let limit = "chargeLimit"
	static let lower = "chargeLowerBound"
	static let forceDischarge = "forceDischarge"
	static let presets = "limitPresets"
	static let lowBatteryAlert = "lowBatteryAlert"
	static let lowBatteryLevel = "lowBatteryLevel"
	static let legacyDeclined = "legacyCleanupDeclined"
	static let onboarded = "onboarded"
}

enum IconStyle: String, CaseIterable, Identifiable {
	case battery, bolt, shield
	var id: String { rawValue }
	var title: String { switch self { case .battery: return "Battery"; case .bolt: return "Bolt"; case .shield: return "Shield" } }
}

extension UserDefaults {
	/// Registered once at launch so `@AppStorage` defaults and manual reads agree.
	static func registerBatteryDefaults() {
		standard.register( defaults: [
			Pref.showPercent: true,
			Pref.iconStyle: IconStyle.battery.rawValue,
			Pref.limit: 80,
			Pref.lower: 75,
			Pref.forceDischarge: false,
			Pref.presets: [ 60, 70, 80, 90 ],
			Pref.lowBatteryAlert: true,
			Pref.lowBatteryLevel: 15,
		] )
	}
}
