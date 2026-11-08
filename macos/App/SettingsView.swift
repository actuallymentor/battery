import SwiftUI

struct SettingsView: View {

	@Bindable var model: AppModel
	@AppStorage( Pref.showPercent ) private var showPercent = true
	@AppStorage( Pref.iconStyle ) private var iconStyle = IconStyle.battery.rawValue
	@AppStorage( Pref.lowBatteryAlert ) private var lowAlert = true
	@AppStorage( Pref.lowBatteryLevel ) private var lowLevel = 15
	@State private var confirmUninstall = false

	var body: some View {
		Form {

			Section( "General" ) {
				Toggle( "Open at login", isOn: Binding( get: { model.launchAtLogin }, set: { model.setLaunchAtLogin( $0 ) } ) )
			}

			Section( "Menu bar" ) {
				Toggle( "Show battery percentage", isOn: $showPercent )
				Picker( "Icon", selection: $iconStyle ) {
					ForEach( IconStyle.allCases ) { Text( $0.title ).tag( $0.rawValue ) }
				}
			}

			Section( "Alerts" ) {
				Toggle( "Low battery notification", isOn: $lowAlert )
				if lowAlert { Stepper( "Alert at \( lowLevel )%", value: $lowLevel, in: 5...50, step: 5 ) }
			}

			Section( "Helper" ) {
				LabeledContent( "Status", value: helperText )
				if let s = model.status {
					LabeledContent( "Version", value: s.daemonVersion )
					LabeledContent( "SMC keys", value: s.smcKeys.isEmpty ? "none found" : s.smcKeys.joined( separator: " " ) )
				}
				Button( "Uninstall Battery…", role: .destructive ) { confirmUninstall = true }
					.confirmationDialog( "Uninstall Battery?", isPresented: $confirmUninstall ) {
						Button( "Restore charging and uninstall", role: .destructive ) { model.uninstall() }
					} message: { Text( "Charging goes back to normal and the helper is removed. Then drag Battery.app to the Trash." ) }
			}

		}
		.formStyle( .grouped )
		.frame( width: 420 )
		.fixedSize( horizontal: false, vertical: true )
	}

	private var helperText: String {
		switch model.helper {
		case .ready: return "Running"
		case .needsApproval: return "Needs approval"
		case .notRegistered: return "Not enabled"
		case .unreachable: return "Not responding"
		case .unknown: return "…"
		}
	}

}
