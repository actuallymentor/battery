import Foundation
import Sparkle

/// Sparkle behind a tiny surface. Opt-in: nothing checks until the user enables it or presses the button.
@MainActor
@Observable
final class Updater {

	/// Pre-release versions (2.0.0-beta.1) are installed by hand: the appcast follows the latest *stable* release, where a beta finds
	/// nothing (today: v1, no appcast). Sparkle stays off, unless a feed is set by hand (`defaults write co.palokaj.battery SUFeedURL …`, update tests).
	static let isBeta = batteryVersion.contains( "-" ) && UserDefaults.standard.string( forKey: "SUFeedURL" ) == nil

	private let controller = SPUStandardUpdaterController( startingUpdater: !Updater.isBeta, updaterDelegate: nil, userDriverDelegate: nil )

	/// Mirrors Sparkle's own setting, so the Settings toggle is observable
	var automatic: Bool {
		didSet { controller.updater.automaticallyChecksForUpdates = automatic }
	}

	init() { automatic = controller.updater.automaticallyChecksForUpdates }

	func check() { controller.checkForUpdates( nil ) }

}
