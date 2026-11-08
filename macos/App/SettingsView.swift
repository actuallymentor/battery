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

			Section( "Schedule" ) {
				Toggle( "Top off to 100% regularly", isOn: Binding( get: { ( model.status?.scheduleDays ?? 0 ) > 0 }, set: { model.setSchedule( days: $0 ? 30 : 0 ) } ) )
				if let days = model.status?.scheduleDays, days > 0 {
					Stepper( "Every \( days ) days", value: Binding( get: { days }, set: { model.setSchedule( days: $0 ) } ), in: 1...90 )
					if let next = model.status?.nextTopOff { LabeledContent( "Next", value: next.formatted( date: .abbreviated, time: .omitted ) ) }
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
					LabeledContent( "Charge control", value: backendName( s.backend ) )
					if let c = s.cycleCount { LabeledContent( "Cycle count", value: "\( c )" ) }
					if let h = s.healthPercent { LabeledContent( "Battery health", value: "\( h )%" ) }
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

	private func backendName( _ b: String ) -> String {
		switch b {
		case "tahoe", "legacy": return "SMC inhibit"
		case "firmwareLimit": return "Firmware limit"
		case "softwareCut": return "Adapter cut (compatibility)"
		case "none": return "Not supported"
		default: return b
		}
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
