import Foundation
import Sparkle

/// Sparkle behind a tiny surface. Opt-in: nothing checks until the user enables it or presses the button.
@MainActor
final class Updater {

	/// Pre-release versions (2.0.0-beta.1) are installed by hand: the appcast follows the latest *stable* release, where a beta finds
	/// nothing (today: v1, no appcast). Sparkle stays off, unless a feed is set by hand (`defaults write co.palokaj.battery SUFeedURL …`, update tests).
	static let isBeta = batteryVersion.contains( "-" ) && UserDefaults.standard.string( forKey: "SUFeedURL" ) == nil

	private let controller = SPUStandardUpdaterController( startingUpdater: !Updater.isBeta, updaterDelegate: nil, userDriverDelegate: nil )

	var automatic: Bool {
		get { controller.updater.automaticallyChecksForUpdates }
		set { controller.updater.automaticallyChecksForUpdates = newValue }
	}

	var canCheck: Bool { controller.updater.canCheckForUpdates }

	func check() { controller.checkForUpdates( nil ) }

}
