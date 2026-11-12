import SwiftUI
import BatteryCore

struct SettingsView: View {

	@Bindable var model: AppModel
	let updater: Updater
	@State private var autoUpdate = false
	@AppStorage( Pref.showPercent ) private var showPercent = true
	@AppStorage( Pref.appearance ) private var appearance = Appearance.system.rawValue
	@AppStorage( Pref.iconStyle ) private var iconStyle = IconStyle.battery.rawValue
	@AppStorage( Pref.lowBatteryAlert ) private var lowAlert = true
	@AppStorage( Pref.lowBatteryLevel ) private var lowLevel = 15
	@State private var confirmUninstall = false

	var body: some View {
		TabView {

			Form {
				Section( "Charge limit" ) {
					VStack( alignment: .leading, spacing: 4 ) {
						LabeledContent( "Stop charging at", value: "\( model.settings.limit )%" )
						Slider( value: Binding( get: { Double( model.settings.limit ) }, set: { model.limitChanged( to: Int( $0 ) ) } ), in: Double( LimitSettings.sliderRange.lowerBound )...Double( LimitSettings.sliderRange.upperBound ), step: 1 )
							.labelsHidden()
							.accessibilityLabel( "Charge limit" ).accessibilityValue( "\( model.settings.limit ) percent" )
					}
					Text( "Charging resumes 5% below the limit." ).font( .caption ).foregroundStyle( .secondary )
					if model.status?.canCutAdapter == true {
						VStack( alignment: .leading, spacing: 2 ) {
							Toggle( "Allow discharge", isOn: Binding( get: { model.settings.force }, set: { model.settings.force = $0; model.commitLimitChange() } ) )
							Text( "While plugged in above the limit, run on the battery instead of the adapter until it drops to the limit. Can conflict with clamshell mode." )
								.font( .caption ).foregroundStyle( .secondary ).fixedSize( horizontal: false, vertical: true )
						}
					}
				}
				Section( "Schedule" ) {
					Toggle( "Top off to 100% regularly", isOn: Binding( get: { ( model.status?.scheduleDays ?? 0 ) > 0 }, set: { model.setSchedule( days: $0 ? 30 : 0 ) } ) )
					if let days = model.status?.scheduleDays, days > 0 {
						Stepper( "Every \( days ) days", value: Binding( get: { days }, set: { model.setSchedule( days: $0 ) } ), in: 1...90 )
						if let next = model.status?.nextTopOff { LabeledContent( "Next", value: next.formatted( date: .abbreviated, time: .omitted ) ) }
					}
					Text( "Charges to 100% once in a while, then returns to your limit. Runs when plugged in." ).font( .caption ).foregroundStyle( .secondary )
				}
				if let s = model.status {
					Section( "Battery" ) {
						if let c = s.cycleCount { LabeledContent( "Cycle count", value: "\( c )" ) }
						if let h = s.healthPercent { LabeledContent( "Health", value: "\( h )%" ) }
						LabeledContent( "Charging", value: s.chargingEnabled == false ? "Disabled" : "Enabled" )
						LabeledContent( "Time remaining", value: s.timeEstimate ?? "No estimate" )
						LabeledContent( "Charge control", value: backendName( s.backend ) )
					}
				}
			}
			.tabItem { Label( "Charging", systemImage: "bolt.batteryblock" ) }

			Form {
				Section( "General" ) {
					Toggle( "Open at login", isOn: Binding( get: { model.launchAtLogin }, set: { model.setLaunchAtLogin( $0 ) } ) )
					Picker( "Appearance", selection: $appearance ) {
						ForEach( Appearance.allCases ) { Text( $0.title ).tag( $0.rawValue ) }
					}
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
			}
			.tabItem { Label( "General", systemImage: "gearshape" ) }

			Form {
				Section( "Helper" ) {
					LabeledContent( "Status", value: helperText )
					if let s = model.status {
						LabeledContent( "Version", value: s.daemonVersion )
						LabeledContent( "SMC keys", value: s.smcKeys.isEmpty ? "none found" : s.smcKeys.joined( separator: " " ) )
					}
				}
				Section( "Command line" ) {
					Toggle( "Use `battery` in Terminal", isOn: Binding( get: { model.cliInstalled }, set: { model.setCLIInstalled( $0 ) } ) )
				}
				Section( "Updates" ) {
					if Updater.isBeta {
						// The feed follows the latest stable release: a beta would only find v1 there (no appcast, an error)
						Text( "Beta builds don't update themselves. New betas are on GitHub." ).font( .caption ).foregroundStyle( .secondary )
						Link( "Open GitHub Releases", destination: URL( string: "https://github.com/actuallymentor/battery/releases" )! )
					} else {
						Toggle( "Check for updates automatically", isOn: Binding( get: { autoUpdate }, set: { autoUpdate = $0; updater.automatic = $0 } ) )
						Button( "Check now" ) { updater.check() }
						Text( "Off by default. Nothing is downloaded or installed without you." ).font( .caption ).foregroundStyle( .secondary )
					}
				}
				.onAppear { autoUpdate = updater.automatic }
				Section {
					Button( "Uninstall Battery…", role: .destructive ) { confirmUninstall = true }
						.confirmationDialog( "Uninstall Battery?", isPresented: $confirmUninstall ) {
							Button( "Restore charging and uninstall", role: .destructive ) { model.uninstall() }
						} message: { Text( "Charging goes back to normal and the helper is removed. Then drag Battery.app to the Trash." ) }
				}
			}
			.tabItem { Label( "Helper", systemImage: "lock.shield" ) }

		}
		.formStyle( .grouped )
		.frame( width: 440, height: 600 )
		.onChange( of: appearance ) { applyAppearance() }
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
