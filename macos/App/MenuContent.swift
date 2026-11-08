import SwiftUI
import BatteryCore

/// The popover: state at a glance, one control for the limit, the one-off actions.
struct MenuContent: View {

	@Bindable var model: AppModel
	@AppStorage( Pref.limit ) private var limit = 80
	@AppStorage( Pref.lower ) private var lower = 75
	@AppStorage( Pref.forceDischarge ) private var force = false
	@AppStorage( Pref.presets ) private var presetsRaw = "60,70,80,90"
	@State private var confirmCalibrate = false
	@State private var customPreset = ""

	var body: some View {
		VStack( alignment: .leading, spacing: 14 ) {

			switch model.helper {
			case .ready: content
			case .unknown: ProgressView().frame( maxWidth: .infinity )
			default: HelperSetup( model: model )
			}

			if !model.legacyLeftovers.isEmpty { LegacyBanner( model: model ) }

			if let error = model.error {
				Label( error, systemImage: "exclamationmark.circle" )
					.font( .caption ).foregroundStyle( .red )
					.onTapGesture { model.dismissError() }
			}

			Divider()
			footer
		}
		.padding( 16 )
		.frame( width: 320 )
	}

	// MARK: Ready state

	@ViewBuilder private var content: some View {
		if let s = model.status {
			header( s )
			if let w = s.warning {
				Label( w, systemImage: "exclamationmark.triangle.fill" )
					.font( .caption ).foregroundStyle( .orange ).fixedSize( horizontal: false, vertical: true )
			}
			if s.backend != "none" {
				limitSection( s )
				actions( s )
			}
		}
	}

	private func header( _ s: BatteryStatus ) -> some View {
		HStack( alignment: .firstTextBaseline ) {
			Text( "\( s.percent )%" ).font( .system( size: 40, weight: .semibold, design: .rounded ) ).monospacedDigit()
			VStack( alignment: .leading, spacing: 2 ) {
				Text( s.headline ).font( .headline )
				Text( detail( s ) ).font( .caption ).foregroundStyle( .secondary )
			}
			Spacer()
		}
	}

	private func detail( _ s: BatteryStatus ) -> String {
		if s.backend == "none" { return "No charge control found on this Mac" }
		var parts = [ String ]()
		if s.remaining != "no estimate" { parts.append( "\( s.remaining ) remaining" ) }
		if let v = s.voltage { parts.append( String( format: "%.2f V", v ) ) }
		return parts.isEmpty ? "Estimating…" : parts.joined( separator: " · " )
	}

	// MARK: Limit

	private func limitSection( _ s: BatteryStatus ) -> some View {
		VStack( alignment: .leading, spacing: 10 ) {

			Toggle( isOn: Binding( get: { s.maintain != nil }, set: { model.applyLimit( enabled: $0 ) } ) ) {
				Text( "Charge limit" ).font( .subheadline.weight( .medium ) )
			}
			.toggleStyle( .switch )
			.disabled( model.busy )

			HStack {
				ForEach( presets, id: \.self ) { p in
					Button( "\( p )%" ) { limit = p; lower = min( lower, p - 1 ); model.commitLimitChange() }
						.buttonStyle( .bordered )
						.tint( limit == p ? .accentColor : .secondary )
						.controlSize( .small )
						.contextMenu { Button( "Remove preset" ) { removePreset( p ) } }
				}
				Spacer()
				Menu {
					Button( "Add current (\( limit )%) as preset" ) { addPreset( limit ) }
					Divider()
					Button( "Reset presets" ) { presetsRaw = "60,70,80,90" }
				} label: { Image( systemName: "ellipsis.circle" ) }
				.menuStyle( .borderlessButton ).fixedSize()
			}

			Slider( value: Binding( get: { Double( limit ) }, set: { limit = Int( $0 ); lower = min( lower, limit - 1 ) } ), in: 20...100, step: 1,
			        onEditingChanged: { editing in if !editing { model.commitLimitChange() } } )

			HStack {
				Text( "Stop at \( limit )%" )
				Spacer()
				Stepper( "Resume below \( lower )%", value: Binding( get: { lower }, set: { lower = min( max( $0, 10 ), limit ); model.commitLimitChange() } ), in: 10...100 )
					.font( .caption )
			}
			.font( .caption )

			if canCutAdapter( s ) {
				Toggle( "Discharge down to the limit when plugged in", isOn: Binding( get: { force }, set: { force = $0; model.commitLimitChange() } ) )
					.font( .caption )
					.help( "Uses the battery instead of the adapter while above the limit. Can conflict with clamshell mode." )
			}
		}
		.padding( 12 )
		.background( .quaternary.opacity( 0.5 ), in: RoundedRectangle( cornerRadius: 10 ) )
	}

	// MARK: One-off actions

	private func actions( _ s: BatteryStatus ) -> some View {
		VStack( alignment: .leading, spacing: 8 ) {
			if s.activity != nil {
				Button { model.recover() } label: { Label( "Cancel and restore charging", systemImage: "xmark.circle" ) }
			} else {
				HStack {
					Button { model.chargeTo( 100 ) } label: { Label( "Charge to 100%", systemImage: "bolt.fill" ) }
					if canCutAdapter( s ) {
						Button { model.dischargeTo( max( limit - 10, 20 ) ) } label: { Label( "Discharge to \( max( limit - 10, 20 ) )%", systemImage: "arrow.down.circle" ) }
					}
				}
				if canCutAdapter( s ) { Button { confirmCalibrate = true } label: { Label( "Calibrate battery…", systemImage: "gauge.with.dots.needle.bottom.50percent" ) }
					.confirmationDialog( "Calibrate battery?", isPresented: $confirmCalibrate ) {
						Button( "Calibrate", role: .destructive ) { model.calibrate() }
					} message: { Text( "Discharges to 15%, charges to 100%, holds for an hour, then returns to your limit. Takes several hours. Keep the Mac awake and plugged in." ) } }
			}
		}
		.buttonStyle( .bordered )
		.controlSize( .small )
		.disabled( model.busy )
	}

	/// Adapter cut keys exist: force discharge, discharge-to and calibrate depend on them
	private func canCutAdapter( _ s: BatteryStatus ) -> Bool { !Set( s.smcKeys ).isDisjoint( with: [ "CHIE", "CH0J", "CH0I" ] ) }

	// MARK: Footer

	private var footer: some View {
		HStack {
			SettingsLink { Text( "Settings…" ) }
				.simultaneousGesture( TapGesture().onEnded { NSApplication.shared.activate( ignoringOtherApps: true ) } )
			Spacer()
			Button( "Quit" ) { NSApplication.shared.terminate( nil ) }
		}
		.buttonStyle( .plain ).font( .caption ).foregroundStyle( .secondary )
	}

	// MARK: Presets (#462)

	private var presets: [ Int ] { presetsRaw.split( separator: "," ).compactMap { Int( $0 ) }.sorted() }

	private func addPreset( _ p: Int ) {
		presetsRaw = Array( Set( presets + [ p ] ) ).sorted().prefix( 6 ).map( String.init ).joined( separator: "," )
	}

	private func removePreset( _ p: Int ) { presetsRaw = presets.filter { $0 != p }.map( String.init ).joined( separator: "," ) }

}

/// Shown instead of the controls until the root helper runs.
struct HelperSetup: View {

	@Bindable var model: AppModel

	var body: some View {
		VStack( alignment: .leading, spacing: 10 ) {
			Label( title, systemImage: "lock.shield" ).font( .headline )
			Text( message ).font( .callout ).foregroundStyle( .secondary ).fixedSize( horizontal: false, vertical: true )
			switch model.helper {
			case .needsApproval:
				Button( "Open Login Items" ) { model.openLoginItems() }.buttonStyle( .borderedProminent )
			case .unreachable:
				Button( "Repair helper" ) { model.repairHelper() }.buttonStyle( .borderedProminent )
			default:
				Button( "Enable helper" ) { model.registerHelper() }.buttonStyle( .borderedProminent )
			}
		}
	}

	private var title: String {
		switch model.helper {
		case .needsApproval: return "Approve the helper"
		case .unreachable: return "Helper not responding"
		default: return "One-time setup"
		}
	}

	private var message: String {
		switch model.helper {
		case .needsApproval: return "In System Settings → General → Login Items & Extensions, switch on Battery under App Background Activity."
		case .unreachable: return "The helper is registered but not answering (often after moving or replacing the app). Repair re-registers it and may ask for approval again."
		default: return "Limiting charge needs a small background helper with admin rights. macOS will ask you to approve it once."
		}
	}

}

/// First launch of v2 on a Mac that still has v1.
struct LegacyBanner: View {

	@Bindable var model: AppModel

	var body: some View {
		VStack( alignment: .leading, spacing: 8 ) {
			Label( "Old version found", systemImage: "arrow.triangle.2.circlepath" ).font( .subheadline.weight( .medium ) )
			Text( "Battery 1.x is still installed. Remove it so the two don't fight over charging? Your settings here are unaffected." )
				.font( .caption ).foregroundStyle( .secondary ).fixedSize( horizontal: false, vertical: true )
			HStack {
				Button( "Remove old version" ) { model.removeLegacy() }.buttonStyle( .borderedProminent )
				Button( "Not now" ) { model.declineLegacyCleanup() }
			}
			.controlSize( .small )
		}
		.padding( 10 )
		.background( .orange.opacity( 0.12 ), in: RoundedRectangle( cornerRadius: 10 ) )
	}

}
