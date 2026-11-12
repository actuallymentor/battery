import SwiftUI
import BatteryCore

struct SettingsView: View {

	@Bindable var model: AppModel
	@Bindable var updater: Updater
	@AppStorage( Pref.showPercent ) private var showPercent = true
	@AppStorage( Pref.appearance ) private var appearance = Appearance.system
	@AppStorage( Pref.iconStyle ) private var iconStyle = IconStyle.battery
	@AppStorage( Pref.lowBatteryAlert ) private var lowAlert = true
	@AppStorage( Pref.lowBatteryLevel ) private var lowLevel = 15
	@State private var confirmUninstall = false

	var body: some View {
		VStack( spacing: 0 ) {
			tabs
			ErrorRow( model: model ).padding( .horizontal, 20 ).padding( .bottom, 12 )
		}
		.frame( width: 440, height: 600 )
		.onChange( of: appearance ) { applyAppearance() }
	}

	private var tabs: some View {
		TabView {

			Form {
				Section( "Charge limit" ) {
					VStack( alignment: .leading, spacing: 4 ) {
						LabeledContent( "Stop charging at", value: "\( model.limit )%" )
						Slider( value: Binding( get: { Double( model.limit ) }, set: { model.limit = Int( $0 ) } ), in: Double( LimitSettings.sliderRange.lowerBound )...Double( LimitSettings.sliderRange.upperBound ), step: 1 )
							.labelsHidden()
							.accessibilityLabel( "Charge limit" ).accessibilityValue( "\( model.limit ) percent" )
					}
					Text( "Charging resumes 5% below the limit." ).font( .caption ).foregroundStyle( .secondary )
					if model.status?.canCutAdapter == true {
						VStack( alignment: .leading, spacing: 2 ) {
							Toggle( "Allow discharge", isOn: $model.allowDischarge ).disabled( model.isPending( .force ) )
							Text( "While plugged in above the limit, run on the battery instead of the adapter until it drops to the limit. Paused while the lid is closed." )
								.font( .caption ).foregroundStyle( .secondary ).fixedSize( horizontal: false, vertical: true )
						}
					}
				}
				Section( "Schedule" ) {
					Toggle( "Top off to 100% regularly", isOn: $model.scheduleOn ).disabled( model.isPending( .schedule ) )
					if model.scheduleOn, model.scheduleDays > 0 {
						Stepper( "Every \( model.scheduleDays ) days", value: $model.scheduleDays, in: 1...90 )
						if let next = model.status?.nextTopOff { LabeledContent( "Next", value: next.formatted( date: .abbreviated, time: .omitted ) ) }
					}
					Text( "Charges to 100% once in a while, then returns to your limit. Runs when plugged in." ).font( .caption ).foregroundStyle( .secondary )
				}
				if model.helper == .ready, let s = model.status {
					Section( "Battery" ) {
						if let c = s.cycleCount { LabeledContent( "Cycle count", value: "\( c )" ) }
						if let h = s.healthPercent { LabeledContent( "Health", value: "\( h )%" ) }
						LabeledContent( "Charging", value: s.chargingEnabled == false ? "Disabled" : "Enabled" )
						LabeledContent( "Time remaining", value: s.timeEstimate ?? "No estimate" )
						LabeledContent( "Charge control", value: s.backend.title )
					}
				}
			}
			.tabItem { Label( "Charging", systemImage: "bolt.batteryblock" ) }

			Form {
				Section( "General" ) {
					Toggle( "Open at login", isOn: $model.launchAtLogin )
					Picker( "Appearance", selection: $appearance ) {
						ForEach( Appearance.allCases ) { Text( $0.title ).tag( $0 ) }
					}
				}
				Section( "Menu bar" ) {
					Toggle( "Show battery percentage", isOn: $showPercent )
					Picker( "Icon", selection: $iconStyle ) {
						ForEach( IconStyle.allCases ) { Text( $0.title ).tag( $0 ) }
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
					LabeledContent( "Status", value: model.helper.short )
					if model.helper == .ready, let s = model.status {
						LabeledContent( "Version", value: s.daemonVersion )
						LabeledContent( "SMC keys", value: s.smcKeys.isEmpty ? "none found" : s.smcKeys.joined( separator: " " ) )
					}
				}
				Section( "Command line" ) {
					Toggle( "Use `battery` in Terminal", isOn: $model.cliInstalled ).disabled( model.isPending( .cli ) )
				}
				Section( "Updates" ) {
					if Updater.isBeta {
						// The feed follows the latest stable release: a beta would only find v1 there (no appcast, an error)
						Text( "Beta builds don't update themselves. New betas are on GitHub." ).font( .caption ).foregroundStyle( .secondary )
						Link( "Open GitHub Releases", destination: URL( string: "https://github.com/actuallymentor/battery/releases" )! )
					} else {
						Toggle( "Check for updates automatically", isOn: $updater.automatic )
						Button( "Check now" ) { updater.check() }
						Text( "Off by default. Nothing is downloaded or installed without you." ).font( .caption ).foregroundStyle( .secondary )
					}
				}
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
	}

}
