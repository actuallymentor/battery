import SwiftUI

/// Setup in a real window: a menu bar popover is easy to miss on first launch. Same content and actions as the popover's
/// `HelperSetup`; once the helper answers it says so and offers Done.
struct SetupWindow: View {

	static let id = "setup"

	@Bindable var model: AppModel
	@Environment( \.dismissWindow ) private var dismissWindow

	var body: some View {
		Group {
			if model.helper == .ready {
				VStack( alignment: .leading, spacing: 10 ) {
					Label( "All set", systemImage: "checkmark.shield" ).font( .headline )
					Text( "Battery limits charging from the menu bar. Change the limit in Settings → Charging." )
						.font( .callout ).foregroundStyle( .secondary ).fixedSize( horizontal: false, vertical: true )
					Button( "Done" ) { dismissWindow( id: Self.id ) }.buttonStyle( .borderedProminent ).keyboardShortcut( .defaultAction )
				}
			} else {
				VStack( alignment: .leading, spacing: 10 ) {
					HelperSetup( model: model )
					ErrorRow( model: model )     // "The helper didn't start…" must show here too, the popover may be closed
				}
			}
		}
		.padding( 20 )
		.frame( width: 360, alignment: .leading )
	}

}

/// Opens the setup window by itself, once per launch, when the helper needs setting up or approving. Lives on the menu bar
/// label: the one view that exists from launch on (the popover's content only exists while it is open).
struct SetupPrompt: ViewModifier {

	@Bindable var model: AppModel
	@Environment( \.openWindow ) private var openWindow

	func body( content: Content ) -> some View {
		content.onChange( of: model.needsSetup, initial: true ) {
			guard model.needsSetup, !model.setupPrompted else { return }
			model.setupPrompted = true
			NSApp.activate()
			openWindow( id: SetupWindow.id )
		}
	}

}
