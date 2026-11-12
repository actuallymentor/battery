import AppKit
import E2EKit
import XCTest

/// The helper's whole life on a real Mac: Settings -> Uninstall, setting up again, and approval revoked / granted in System Settings.
/// It really unregisters the root helper, so it only runs when asked (`scripts/e2e.sh lifecycle`, which sets E2E_LIFECYCLE=1).
///
/// Revoking approval needs the admin password in System Settings. The password never passes through the test: the test checks that
/// System Settings is frontmost with its Password field focused, drops /tmp/e2e/password-wanted and waits for /tmp/e2e/password-typed;
/// scripts/e2e.sh answers with `babysit mac unlock`. Granting it back needs no password.
final class LifecycleTests: XCTestCase {

	private let daemon = "co.palokaj.battery.daemon"
	private let settingsID = "com.apple.systempreferences"
	private let wanted = "/tmp/e2e/password-wanted", typed = "/tmp/e2e/password-typed", refused = "/tmp/e2e/password-refused"

	override func setUpWithError() throws {
		try XCTSkipUnless( ProcessInfo.processInfo.environment[ "E2E_LIFECYCLE" ] == "1", "Unregisters the helper: run scripts/e2e.sh lifecycle" )
		continueAfterFailure = false
		XCTAssertTrue( AX.trusted, "Runner has no Accessibility permission" )
		XCTAssertFalse( Screen.locked, "Screen is locked" )
		[ wanted, typed, refused ].forEach { try? FileManager.default.removeItem( atPath: $0 ) }
		try? FileManager.default.createDirectory( atPath: "/tmp/e2e", withIntermediateDirectories: true )
	}

	/// Whatever a test did, the Mac ends with the helper approved, registered and answering
	override func tearDown() {
		guard ProcessInfo.processInfo.environment[ "E2E_LIFECYCLE" ] == "1" else { return }
		if !helperUp() {
			settingsApp?.find { $0.role == "AXButton" && $0.title == "Cancel" }?.press()     // a password sheet left open
			if let s = loginSwitch(), !s.on { s.press() }
			GUI.launch()
			enableButton()?.press()
			_ = eventually( 30 ) { self.helperUp() ? true : nil }
		}
		quitSystemSettings()
		CLI.restore()
	}

	// MARK: Helpers

	/// The CLI waits up to 15s for an absent helper: cap it, polls repeat anyway
	private func helperUp() -> Bool { CLI.battery( [ "status" ], timeout: 5 ).ok }
	private var registered: Bool { sh( "/bin/launchctl", [ "print", "system/\( daemon )" ] ).ok }

	private func enableButton() -> AX? { GUI.openPopover()?.find( role: "AXButton", label: "Enable helper" ) }

	/// Login Items -> App Background Activity -> the "Battery" switch
	private var settingsApp: AX? { AX.app( bundleID: settingsID ) }
	private var currentSwitch: AX? { settingsApp?.find { $0.identifier == "background-switch-Battery" } }

	/// Opens the pane (brings System Settings forward) and waits for the switch
	private func loginSwitch() -> AX? {
		_ = sh( "/usr/bin/open", [ "x-apple.systempreferences:com.apple.LoginItems-Settings.extension" ] )
		return eventually( 15 ) { self.currentSwitch }
	}

	private func quitSystemSettings() {
		NSRunningApplication.runningApplications( withBundleIdentifier: settingsID ).forEach { $0.terminate() }
	}

	// MARK: Tests

	/// Settings -> Helper -> Uninstall: charging back to macOS, helper gone from launchd, app quits. Opening it again offers setup, one click brings the helper back.
	func testUninstallThenSetUpAgain() throws {
		XCTAssertTrue( GUI.launch() )
		XCTAssertTrue( helperUp(), "needs a working helper to start from" )
		XCTAssertTrue( registered )

		XCTAssertNotNil( GUI.openSettings( tab: "Helper" ), "Settings window did not open" )
		let uninstall = try XCTUnwrap( eventually( 5 ) { GUI.button( "Uninstall Battery…" ) } )
		uninstall.press()
		let confirm = try XCTUnwrap( eventually( 5 ) { GUI.button( "Restore charging and uninstall" ) }, "no confirmation sheet:\n\( GUI.snapshot )" )
		confirm.press()

		XCTAssertNotNil( eventually( 20 ) { GUI.app == nil ? true : nil }, "the app should quit after uninstalling" )
		XCTAssertNotNil( eventually( 20 ) { self.registered ? nil : true }, "the helper should be gone from launchd" )
		XCTAssertFalse( helperUp(), "the CLI should find no helper" )

		// Back the way a new user starts: setup screen, one click, helper answering
		XCTAssertTrue( GUI.launch() )
		let enable = try XCTUnwrap( eventually( 15 ) { self.enableButton() }, "no setup screen after uninstall:\n\( GUI.snapshot )" )
		XCTAssertNotNil( GUI.popover?.find( role: "AXStaticText", label: "One-time setup" ) )
		enable.press()
		XCTAssertNotNil( eventually( 30 ) { self.helperUp() ? true : nil }, "helper did not come back:\n\( GUI.snapshot )" )
		XCTAssertNotNil( eventually( 15 ) { GUI.openPopover()?.find( role: "AXCheckBox", label: "Charge limit" ) }, "popover should show the limit switch again" )
		XCTAssertTrue( registered )
	}

	/// Login Items switch off (admin password): helper gone, app asks for approval. Switch on (no password): helper answers again.
	func testRevokedApprovalIsNoticedAndRestored() throws {
		XCTAssertTrue( GUI.launch() )
		XCTAssertTrue( helperUp(), "needs a working helper to start from" )

		let toggle = try XCTUnwrap( loginSwitch(), "Battery switch not found in Login Items" )
		XCTAssertTrue( toggle.on, "helper should start approved" )
		toggle.press()

		// Either the password sheet comes up, or macOS still has a recent authorization cached and the switch just flips
		let sw = try XCTUnwrap( settingsApp )
		_ = sh( "/usr/bin/open", [ "-a", "System Settings" ] )
		let asked = eventually( 10 ) { () -> Bool? in
			if sw.find( { $0.role == "AXTextField" && $0.title == "Password" } ) != nil { return true }
			return sw.find( { $0.identifier == "background-switch-Battery" } )?.on == false ? false : nil
		}
		XCTAssertNotNil( asked, "neither a password sheet nor a switched-off toggle:\n\( sw.windows.map { $0.dump( depth: 6 ) }.joined() )" )

		if asked == true {
			// Only type when System Settings is frontmost and its Password field has focus
			let ready = eventually( 10 ) {
				NSWorkspace.shared.frontmostApplication?.bundleIdentifier == self.settingsID && sw.focused?.title == "Password" ? true : nil
			}
			guard ready != nil else {
				sw.find { $0.role == "AXButton" && $0.title == "Cancel" }?.press()
				return XCTFail( "Password field is not focused in the frontmost System Settings, not typing anything" )
			}
			FileManager.default.createFile( atPath: wanted, contents: nil )
			let answer = eventually( 90, every: 1 ) { [ typed, refused ].first { FileManager.default.fileExists( atPath: $0 ) } }
			guard answer == typed else {
				sw.find { $0.role == "AXButton" && $0.title == "Cancel" }?.press()
				return XCTFail( answer == refused ? "System Settings lost focus before typing, nothing typed" : "nobody typed the password (scripts/e2e.sh lifecycle does)" )
			}
			// The sheet may already have taken the password on its own
			eventually( 5 ) { sw.find { $0.role == "AXButton" && $0.title == "Modify Settings" } }?.press()
		}

		XCTAssertNotNil( eventually( 20 ) { self.currentSwitch?.on == false ? true : nil }, "switch should be off" )
		XCTAssertNotNil( eventually( 20 ) { self.helperUp() ? nil : true }, "helper should stop answering once approval is revoked" )
		XCTAssertNotNil( eventually( 20 ) { GUI.openPopover()?.find( role: "AXStaticText", label: "Approve the helper" ) }, "app should ask for approval:\n\( GUI.snapshot )" )
		XCTAssertNotNil( GUI.popover?.find( role: "AXButton", label: "Open Login Items" ) )

		// Granting needs no password
		try XCTUnwrap( loginSwitch() ).press()
		XCTAssertNotNil( eventually( 30 ) { self.helperUp() ? true : nil }, "helper should answer once approved again" )
		XCTAssertNotNil( eventually( 15 ) { GUI.openPopover()?.find( role: "AXCheckBox", label: "Charge limit" ) } )
	}

}
