import SwiftUI
import BatteryCore

/// The popover is one line: the limit switch and a gear. The limit value, discharge option, one-off actions, Settings and Quit live behind the gear / in Settings. The charge level is in the menu bar icon.
struct MenuContent: View {

	@Bindable var model: AppModel
	@State private var confirmCalibrate = false
	@Environment( \.openSettings ) private var openSettings

	var body: some View {
		VStack( alignment: .leading, spacing: 14 ) {

			topRow

			switch model.helper {
			case .ready: content
			case .unknown: ProgressView().frame( maxWidth: .infinity )
			default: HelperSetup( model: model )
			}

			if !model.legacyLeftovers.isEmpty { LegacyBanner( model: model ) }

			if let error = model.error {
				Button { model.dismissError() } label: { Label( error, systemImage: "exclamationmark.circle" ).multilineTextAlignment( .leading ) }
					.buttonStyle( .plain ).font( .caption ).foregroundStyle( .red )
					.accessibilityHint( "Dismiss" )
			}
		}
		.padding( 16 )
		.frame( width: 270 )
		.confirmationDialog( "Calibrate battery?", isPresented: $confirmCalibrate ) {
			Button( "Calibrate", role: .destructive ) { model.calibrate() }
		} message: { Text( "Discharges to 15%, charges to 100%, holds for an hour, then returns to your limit. Takes several hours. Keep the Mac awake and plugged in." ) }
	}

	/// One line: the limit switch on the left, the gear on the right. The limit value itself is set in Settings.
	private var topRow: some View {
		HStack( spacing: 10 ) {
			if model.helper == .ready, let s = model.status, s.canLimit {
				Text( "Charge limit \( model.settings.limit )%" ).font( .body )
				Spacer( minLength: 8 )
				Toggle( "Charge limit", isOn: Binding( get: { s.maintain != nil }, set: { model.applyLimit( enabled: $0 ) } ) )
					.labelsHidden().toggleStyle( .switch ).controlSize( .small )
					.disabled( model.busy )
			} else {
				Spacer()
			}
			gear
		}
	}

	// MARK: Ready state

	@ViewBuilder private var content: some View {
		if let s = model.status {
			if let w = s.warning {
				Label( w, systemImage: "exclamationmark.triangle.fill" )
					.font( .caption ).foregroundStyle( .orange ).fixedSize( horizontal: false, vertical: true )
			}
			if s.canLimit { activity( s ) }
		}
	}

	// MARK: Gear menu: one-off actions, Settings, Quit

	private var gear: some View {
		Menu {
			if let s = model.status, s.canLimit, s.activity == nil {
				Button { model.chargeTo( 100 ) } label: { Label( "Charge to 100%", systemImage: "bolt.fill" ) }
				if s.canCutAdapter {
					Button { model.dischargeTo( model.settings.dischargeTarget ) } label: { Label( "Discharge to \( model.settings.dischargeTarget )%", systemImage: "arrow.down.circle" ) }
					Button { confirmCalibrate = true } label: { Label( "Calibrate battery…", systemImage: "gauge.with.dots.needle.bottom.50percent" ) }
				}
				Divider()
			}
			Button( "Settings…" ) { NSApplication.shared.activate( ignoringOtherApps: true ); openSettings() }
			Button( "Quit" ) { NSApplication.shared.terminate( nil ) }
		} label: { Image( systemName: "gearshape" ).frame( width: 28, height: 28 ).contentShape( Rectangle() ) }
		.menuStyle( .borderlessButton ).menuIndicator( .hidden ).fixedSize()
		.accessibilityLabel( "Actions and settings" ).help( "Actions and settings" )
		.disabled( model.busy )
	}

	/// A running job: say so, and offer the way out (starting jobs lives in the gear menu)
	@ViewBuilder private func activity( _ s: BatteryStatus ) -> some View {
		if let activity = s.activity {
			VStack( alignment: .leading, spacing: 8 ) {
				Text( activity ).font( .caption ).foregroundStyle( .secondary )
				Button { model.recover() } label: { Label( "Cancel and restore charging", systemImage: "xmark.circle" ) }
					.buttonStyle( .bordered ).controlSize( .small ).disabled( model.busy )
			}
		}
	}

}

/// Shown instead of the controls until the root helper runs.
struct HelperSetup: View {

	@Bindable var model: AppModel

	var body: some View {
		VStack( alignment: .leading, spacing: 10 ) {
			Label( title, systemImage: "lock.shield" ).font( .headline )
			Text( message ).font( .callout ).foregroundStyle( .secondary ).fixedSize( horizontal: false, vertical: true )
			if model.limitWasActive {
				Text( "Your charge limit may keep the battery from charging until the helper runs again." ).font( .callout ).foregroundStyle( .orange ).fixedSize( horizontal: false, vertical: true )
			}
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
