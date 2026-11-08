import Foundation
import Sparkle

/// Sparkle behind a tiny surface. Opt-in: nothing checks until the user enables it or presses the button.
@MainActor
final class Updater {

	private let controller = SPUStandardUpdaterController( startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil )

	var automatic: Bool {
		get { controller.updater.automaticallyChecksForUpdates }
		set { controller.updater.automaticallyChecksForUpdates = newValue }
	}

	var canCheck: Bool { controller.updater.canCheckForUpdates }

	func check() { controller.checkForUpdates( nil ) }

}
