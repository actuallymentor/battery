import SwiftUI
import BatteryCore

@main
struct BatteryApp: App {

	@State private var model = AppModel()
	private let updater = Updater()
	@AppStorage( Pref.showPercent ) private var showPercent = true
	@AppStorage( Pref.iconStyle ) private var iconStyle = IconStyle.battery.rawValue
	@AppStorage( Pref.appearance ) private var appearance = Appearance.system.rawValue

	var body: some Scene {

		MenuBarExtra {
			MenuContent( model: model )
		} label: {
			MenuBarLabel( status: model.status, helper: model.helper, showPercent: showPercent, style: IconStyle( rawValue: iconStyle ) ?? .battery )
				.onChange( of: appearance, initial: true ) { applyAppearance() }
		}
		.menuBarExtraStyle( .window )

		Settings { SettingsView( model: model, updater: updater ) }

	}

}

/// Menu bar item: glyph (+ percent). Warning glyph when the helper is not usable.
struct MenuBarLabel: View {

	let status: BatteryStatus?
	let helper: AppModel.Helper
	let showPercent: Bool
	let style: IconStyle

	var body: some View {
		HStack( spacing: 3 ) {
			Image( systemName: symbol )
			if showPercent, let status { Text( "\( status.percent )%" ).monospacedDigit() }
		}
	}

	private var symbol: String {
		guard helper == .ready, let s = status else { return "exclamationmark.triangle" }
		switch style {
		case .bolt: return s.chargingEnabled == false ? "pause.circle" : "bolt.fill"
		case .shield: return s.maintain != nil ? "shield.lefthalf.filled" : "shield"
		case .battery:
			if s.acAttached && s.chargingEnabled != false && s.percent < 100 { return "battery.100percent.bolt" }
			switch s.percent {
			case ..<13: return "battery.0percent"
			case ..<38: return "battery.25percent"
			case ..<63: return "battery.50percent"
			case ..<88: return "battery.75percent"
			default: return "battery.100percent"
			}
		}
	}

}

/// App-wide override of the device theme (nil = follow the system)
@MainActor func applyAppearance() {
	NSApp.appearance = ( Appearance( rawValue: UserDefaults.standard.string( forKey: Pref.appearance ) ?? "" ) ?? .system ).nsAppearance
}
