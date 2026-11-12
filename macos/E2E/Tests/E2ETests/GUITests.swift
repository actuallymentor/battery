import E2EKit
import XCTest

/// The real Battery.app, driven through macOS accessibility like a user would, verified against the real helper via the CLI.
/// Needs: Accessibility granted to the runner (Terminal), an unlocked screen, scripts/e2e.sh does both.
final class GUITests: E2ECase {

	override func setUp() {
		super.setUp()
		XCTAssertTrue( AX.trusted, "Runner has no Accessibility permission (System Settings -> Privacy & Security -> Accessibility)" )
		XCTAssertFalse( Screen.locked, "Screen is locked, the GUI is invisible to Accessibility" )
		XCTAssertTrue( GUI.launch(), "Battery.app did not start" )
		GUI.dismissSheets()
		GUI.closeSettings()
		GUI.closePopover()
	}

	override func tearDown() {
		GUI.dismissSheets()
		GUI.closeSettings()
		GUI.closePopover()
		super.tearDown()
	}

	private func csv() -> CLI.Csv { CLI.csv()! }

	// MARK: Menu bar item

	func testMenuBarItemShowsPercentAndStatusTooltip() throws {
		let item = try XCTUnwrap( GUI.menuBarItem )
		let shown = Int( item.title.dropLast() )
		XCTAssertNotNil( shown, "menu bar title should be a percentage, got \( item.title )" )
		XCTAssertLessThanOrEqual( abs( ( shown ?? -99 ) - csv().percent ), 1 )
		XCTAssertFalse( item.help.isEmpty, "the tooltip carries the status line" )
	}

	func testTooltipTracksChargeState() throws {
		CLI.battery( "maintain", "80" )
		let held = eventually( 15 ) { GUI.menuBarItem?.help.contains( "Holding at limit" ) == true ? true : nil }
		XCTAssertNotNil( held, "plugged in, limit reached: tooltip should say so, got \( GUI.menuBarItem?.help ?? "nil" )" )
		CLI.battery( "maintain", "stop" )
		XCTAssertNotNil( eventually( 15 ) { GUI.menuBarItem?.help.contains( "Holding" ) == false ? true : nil } )
	}

	// MARK: Popover

	func testPopoverIsOneRowSwitchAndGear() throws {
		let p = try XCTUnwrap( GUI.openPopover() )
		XCTAssertNotNil( GUI.limitSwitch )
		XCTAssertNotNil( GUI.gear )
		XCTAssertNotNil( GUI.limitText )
		XCTAssertNil( p.find { $0.role == "AXSlider" }, "the slider lives in Settings, not the popover" )
		XCTAssertNil( p.find { $0.role == "AXButton" && $0.title == "Charge to 100%" }, "one-off actions live in the gear menu" )
	}

	func testSwitchOnHoldsTheLimitAndOffReleasesIt() throws {
		GUI.openPopover()
		let limit = try XCTUnwrap( GUI.limitText )
		if GUI.limitSwitch?.on == true { GUI.limitSwitch?.press() }
		XCTAssertNotNil( eventually( 10 ) { csv().maintain.isEmpty ? true : nil } )

		XCTAssertTrue( GUI.limitSwitch?.press() == true )
		XCTAssertNotNil( eventually( 10 ) { csv().maintain.isEmpty ? nil : true }, "switch on should start maintain in the helper" )
		XCTAssertEqual( csv().maintain, "\( max( limit - 5, 10 ) )-\( limit )", "fixed 5 point band below the limit" )
		XCTAssertEqual( GUI.limitSwitch?.on, true )

		GUI.limitSwitch?.press()
		XCTAssertNotNil( eventually( 10 ) { csv().maintain.isEmpty ? true : nil }, "switch off should stop maintain" )
		XCTAssertTrue( csv().chargingEnabled )
	}

	func testCLIChangesShowUpInTheSwitch() throws {
		GUI.openPopover()
		CLI.battery( "maintain", "80" )
		XCTAssertNotNil( eventually( 15 ) { GUI.limitSwitch?.on == true ? true : nil }, "the app should adopt a limit set from the CLI" )
		XCTAssertEqual( GUI.limitText, 80 )
		CLI.battery( "maintain", "stop" )
		XCTAssertNotNil( eventually( 15 ) { GUI.limitSwitch?.on == false ? true : nil } )
	}

	// MARK: Gear menu

	func testGearMenuHasStatusHeaderActionsSettingsAndQuit() throws {
		let items = GUI.gearItems()
		XCTAssertFalse( items.isEmpty, "gear menu did not open" )
		XCTAssertFalse( try XCTUnwrap( items.first ).isEmpty, "first row is the status line" )
		XCTAssertTrue( items.contains( "Charge to 100%" ) )
		XCTAssertTrue( items.contains { $0.hasPrefix( "Settings" ) } )
		XCTAssertTrue( items.contains( "Quit" ) )
		if Self.canCutAdapter {
			XCTAssertTrue( items.contains { $0.hasPrefix( "Discharge to" ) } )
			XCTAssertTrue( items.contains { $0.hasPrefix( "Calibrate" ) } )
		}
	}

	func testGearStatusLineMatchesTheHelperState() throws {
		CLI.battery( "maintain", "80" )
		_ = eventually( 15 ) { csv().chargingEnabled ? nil : true }
		let header = try XCTUnwrap( eventually( 10 ) { GUI.gearItems().first.flatMap { $0.hasPrefix( "Holding at limit" ) ? $0 : nil } }, "gear header should read Holding at limit" )
		XCTAssertTrue( header.hasPrefix( "Holding at limit" ), header )
	}

	/// How many times the helper log says a job of this kind started: the one place a job at 100% leaves a trace (it finishes instantly)
	private func jobStarts( _ text: String ) -> Int { CLI.battery( "logs", "400" ).out.components( separatedBy: "job start: \( text )" ).count - 1 }

	func testChargeTo100FromGearStartsAJobInTheHelper() throws {
		let before = jobStarts( "Charging to 100%" )
		XCTAssertTrue( GUI.pick( "Charge to 100%" ) )
		XCTAssertNotNil( eventually( 10 ) { jobStarts( "Charging to 100%" ) > before ? true : nil }, "the helper never started the charge job" )
		// Below 100% the job keeps running, and the popover offers the way out
		if CLI.battery( "status" ).out.lowercased().contains( "charging to" ) {
			GUI.openPopover()
			let cancel = try XCTUnwrap( eventually( 10 ) { GUI.cancelJob }, "a running job offers the way out" )
			XCTAssertTrue( cancel.press() )
			XCTAssertNotNil( eventually( 10 ) { CLI.battery( "status" ).out.lowercased().contains( "charging to" ) ? nil : true } )
		}
	}

	func testDischargeFromGearRunsAJobAndCancelRestores() throws {
		try XCTSkipUnless( Self.canCutAdapter, "this Mac cannot cut the adapter" )
		try XCTSkipUnless( csv().percent > 40, "battery too low" )
		XCTAssertTrue( GUI.pick( "Discharge to" ) )
		XCTAssertNotNil( eventually( 10 ) { CLI.battery( "status" ).out.contains( "ischarging to" ) ? true : nil } )
		GUI.openPopover()
		let cancel = try XCTUnwrap( eventually( 10 ) { GUI.cancelJob }, "a running job offers the way out" )
		XCTAssertTrue( cancel.press() )
		XCTAssertNotNil( eventually( 20 ) { csv().discharging == "not discharging" ? true : nil } )
	}

	func testCalibrateAsksFirstAndCancelStartsNothing() throws {
		try XCTSkipUnless( Self.canCutAdapter, "calibration needs adapter control" )
		XCTAssertTrue( GUI.pick( "Calibrate" ) )
		let cancel = try XCTUnwrap( eventually( 5 ) { GUI.button( "Cancel" ) }, "calibrate must ask for confirmation" )
		XCTAssertNotNil( GUI.button( "Calibrate" ), "the destructive confirm button" )
		XCTAssertTrue( cancel.press() )
		Thread.sleep( forTimeInterval: 1.5 )
		XCTAssertFalse( CLI.battery( "status" ).out.lowercased().contains( "calibrat" ), "cancelling must not start calibration" )
	}

	// MARK: Settings: Charging

	func testSettingsOpensOnChargingTab() throws {
		let w = try XCTUnwrap( GUI.openSettings( tab: "Charging" ), GUI.snapshot )
		XCTAssertNotNil( w.find( role: "AXSlider", label: "Charge limit" ) )
		XCTAssertNotNil( GUI.toggle( "Top off to 100% regularly" ) )
		XCTAssertEqual( GUI.toggle( "Allow discharge" ) != nil, Self.canCutAdapter, "Allow discharge only exists on Macs that can cut the adapter" )
	}

	func testSliderMovesTheLimitInTheHelperLive() throws {
		let w = try XCTUnwrap( GUI.openSettings( tab: "Charging" ), GUI.snapshot )
		let slider = try XCTUnwrap( w.find( role: "AXSlider", label: "Charge limit" ) )
		CLI.battery( "maintain", "80" )
		// The app has adopted the helper's limit once its status refreshes (the Battery rows follow the same poll)
		_ = eventually( 15 ) { slider.number == 80 && GUI.row( "Charging" ) == "Disabled" ? true : nil }
		XCTAssertTrue( slider.slide( to: 70 ), "slider should step to 70, is at \( slider.number ?? -1 )" )
		XCTAssertNotNil( eventually( 10 ) { csv().maintain == "65-70" ? true : nil }, "moving the slider while the limit is on re-applies it: got \( csv().maintain )" )
	}

	/// A mouse drag applies once, on release: pausing on the way (longer than the keyboard debounce) must not reach the helper
	func testSliderDragAppliesOnlyOnRelease() throws {
		let w = try XCTUnwrap( GUI.openSettings( tab: "Charging" ), GUI.snapshot )
		let slider = try XCTUnwrap( w.find( role: "AXSlider", label: "Charge limit" ) )
		CLI.battery( "maintain", "80" )
		_ = eventually( 15 ) { slider.number == 80 && GUI.row( "Charging" ) == "Disabled" ? true : nil }
		let f = try XCTUnwrap( slider.frame )
		let before = csv().maintain

		// Where a value sits on the track (the knob's travel is inset by half a knob at each end; close enough for a 20-100 range)
		func x( _ v: Double ) -> CGFloat { f.minX + 10 + ( f.width - 20 ) * CGFloat( ( v - 20 ) / 80 ) }
		let start = CGPoint( x: x( 80 ), y: f.midY ), pause = CGPoint( x: x( 50 ), y: f.midY ), end = CGPoint( x: x( 60 ), y: f.midY )

		Mouse.down( start )
		Mouse.drag( from: start, to: pause )
		Thread.sleep( forTimeInterval: 1.5 )
		XCTAssertLessThan( slider.number ?? 80, 70, "the drag should move the slider" )
		XCTAssertEqual( csv().maintain, before, "a value passed mid-drag reached the helper" )

		Mouse.drag( from: pause, to: end )
		Mouse.up( end )
		let applied = eventually( 10 ) { () -> String? in let m = csv().maintain; return m != before ? m : nil }
		let upper = applied.flatMap { Int( $0.split( separator: "-" ).last ?? "" ) }
		XCTAssertNotNil( upper, "release should apply the new limit, still \( csv().maintain )" )
		XCTAssertEqual( Double( upper ?? 0 ), slider.number ?? -1, "the helper gets what the slider shows" )
		XCTAssertTrue( ( 55...65 ).contains( upper ?? 0 ), "released near 60, got \( upper ?? -1 )" )
	}

	func testAllowDischargeToggleSticks() throws {
		try XCTSkipUnless( Self.canCutAdapter, "this Mac cannot cut the adapter" )
		let w = try XCTUnwrap( GUI.openSettings( tab: "Charging" ), GUI.snapshot )
		let toggle = try XCTUnwrap( GUI.toggle( "Allow discharge", in: w ) )
		let was = toggle.on
		XCTAssertTrue( toggle.press() )
		XCTAssertNotNil( eventually( 5 ) { GUI.toggle( "Allow discharge" )?.on == !was ? true : nil } )
		GUI.toggle( "Allow discharge" )?.press()
		XCTAssertNotNil( eventually( 5 ) { GUI.toggle( "Allow discharge" )?.on == was ? true : nil } )
	}

	func testTopOffScheduleToggleReachesTheHelper() throws {
		let w = try XCTUnwrap( GUI.openSettings( tab: "Charging" ), GUI.snapshot )
		let toggle = try XCTUnwrap( GUI.toggle( "Top off to 100% regularly", in: w ) )
		if toggle.on { toggle.press(); _ = eventually( 5 ) { toggle.on ? nil : true } }
		XCTAssertTrue( toggle.press() )
		let days = { try? String( contentsOfFile: "/var/db/co.palokaj.battery/schedule", encoding: .utf8 ).split( separator: " " ).first.map( String.init ) }
		XCTAssertNotNil( eventually( 10 ) { days() != "0" ? true : nil }, "schedule should be on in the helper" )
		toggle.press()
		XCTAssertNotNil( eventually( 10 ) { days() == "0" ? true : nil }, "schedule should be off again" )
	}

	func testBatterySectionMatchesTheHelper() throws {
		_ = try XCTUnwrap( GUI.openSettings( tab: "Charging" ), GUI.snapshot )
		let c = csv()
		XCTAssertEqual( GUI.row( "Charging" ), c.chargingEnabled ? "Enabled" : "Disabled" )
		XCTAssertNotNil( Int( GUI.row( "Cycle count" ) ?? "" ), "cycle count is a number" )
		XCTAssertNotNil( GUI.row( "Time remaining" ) )
		XCTAssertNotNil( GUI.row( "Charge control" ) )
		CLI.battery( "charging", "off" )
		XCTAssertNotNil( eventually( 15 ) { GUI.row( "Charging" ) == "Disabled" ? true : nil }, "the row follows the helper" )
	}

	// MARK: Settings: General and Helper

	func testGeneralTabHasTheExpectedControls() throws {
		let w = try XCTUnwrap( GUI.openSettings( tab: "General" ) )
		for label in [ "Open at login", "Show battery percentage", "Low battery notification" ] {
			XCTAssertNotNil( GUI.toggle( label, in: w ), "\( label ) toggle missing" )
		}
		XCTAssertNotNil( w.find { $0.label.contains( "Appearance" ) || ( $0.value as? String ) == "Appearance" } )
	}

	func testShowPercentageToggleChangesTheMenuBarTitle() throws {
		let w = try XCTUnwrap( GUI.openSettings( tab: "General" ) )
		let toggle = try XCTUnwrap( GUI.toggle( "Show battery percentage", in: w ) )
		let was = toggle.on
		toggle.press()
		let flipped = eventually( 5 ) { ( GUI.menuBarItem?.title.contains( "%" ) == true ) == !was ? true : nil }
		toggle.press()
		XCTAssertNotNil( flipped, "the menu bar title should gain or lose the percentage" )
		XCTAssertNotNil( eventually( 5 ) { ( GUI.menuBarItem?.title.contains( "%" ) == true ) == was ? true : nil } )
	}

	func testHelperTabReportsAReadyHelper() throws {
		let w = try XCTUnwrap( GUI.openSettings( tab: "Helper" ) )
		let texts = w.all { $0.role == "AXStaticText" }.compactMap { $0.value as? String }
		XCTAssertTrue( texts.contains { $0.contains( "2.0." ) }, "helper version should show, saw \( texts )" )
	}

	/// The switch flips on the click itself (it used to wait a poll for the helper, inviting repeat clicks), then the link follows
	func testTerminalSwitchFlipsAtOnceAndTheLinkFollows() throws {
		_ = try XCTUnwrap( GUI.openSettings( tab: "Helper" ) )
		let link = "/usr/local/bin/battery"
		let linked = { ( try? FileManager.default.destinationOfSymbolicLink( atPath: link ) ) != nil }
		// The label is markdown ("Use `battery` in Terminal"): match on the plain tail, as the switch or its label text
		let terminalSwitch = { GUI.settings?.find( role: "AXCheckBox", label: "in Terminal", contains: true ) ?? GUI.toggle( "Use battery in Terminal" ) }
		let was = linked()
		defer { if linked() != was { terminalSwitch()?.press(); _ = eventually( 5 ) { linked() == was ? true : nil } } }

		for want in [ !was, was ] {
			let toggle = try XCTUnwrap( terminalSwitch(), GUI.snapshot )
			XCTAssertEqual( toggle.on, !want )
			toggle.press()
			XCTAssertNotNil( eventually( 0.5, every: 0.05 ) { terminalSwitch()?.on == want ? true : nil }, "the switch should flip right away" )
			XCTAssertNotNil( eventually( 5 ) { linked() == want ? true : nil }, "the helper should \( want ? "add" : "remove" ) \( link )" )
			XCTAssertNotNil( eventually( 5 ) { terminalSwitch()?.enabled == true ? true : nil }, "the switch should unlock once done" )
		}
	}

	/// The feed follows stable releases only: a beta must not offer a check that can only fail
	func testBetaHasNoUpdateCheck() throws {
		try XCTSkipUnless( CLI.battery( "version" ).out.contains( "-" ), "stable build" )
		let w = try XCTUnwrap( GUI.openSettings( tab: "Helper" ) )
		XCTAssertNil( w.find( role: "AXButton", label: "Check now" ), "a beta should not offer Check now" )
		XCTAssertNotNil( w.find( role: "AXStaticText", label: "Beta builds don't update themselves", contains: true ) )
	}

	// MARK: App lifecycle

	func testQuitAndRelaunchKeepsTheLimit() throws {
		CLI.battery( "maintain", "80" )
		XCTAssertTrue( GUI.pick( "Quit" ) )
		XCTAssertNotNil( eventually( 10 ) { GUI.app == nil ? true : nil }, "Quit should end the app" )
		XCTAssertEqual( csv().maintain, "80", "the helper keeps the limit with no app running" )
		XCTAssertTrue( GUI.launch() )
		GUI.openPopover()
		XCTAssertNotNil( eventually( 15 ) { GUI.limitSwitch?.on == true ? true : nil }, "relaunched app shows the limit the helper kept" )
		XCTAssertEqual( GUI.limitText, 80 )
	}

}
