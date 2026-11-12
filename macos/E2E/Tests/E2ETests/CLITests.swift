import E2EKit
import XCTest

/// The shipped `battery` binary against the real root helper. Every assertion reads state the way a user would: CLI output.
final class CLITests: E2ECase {

	private func csv( file: StaticString = #filePath, line: UInt = #line ) -> CLI.Csv {
		guard let c = CLI.csv() else { XCTFail( "status_csv unreadable", file: file, line: line ); fatalError() }
		return c
	}

	// MARK: Read-only commands

	func testVersionMatchesInstalledApp() throws {
		let plist = "/Applications/Battery.app/Contents/Info.plist"
		let app = sh( "/usr/bin/plutil", [ "-extract", "CFBundleShortVersionString", "raw", plist ] ).out
		XCTAssertEqual( CLI.battery( "version" ).out, app )
		XCTAssertEqual( CLI.battery( "--version" ).out, app )
	}

	func testHelpListsEveryCommand() {
		let help = CLI.battery( "help" ).out
		for c in [ "status", "logs", "maintain", "charging", "adapter", "charge", "discharge", "calibrate", "schedule", "uninstall" ] {
			XCTAssertTrue( help.contains( "battery \( c )" ), "help is missing \( c )" )
		}
		XCTAssertEqual( CLI.battery().out, help, "no arguments prints help" )
	}

	func testStatusIsOneLineWithPercentVoltageAndSmcState() {
		let s = CLI.battery( "status" )
		XCTAssertTrue( s.ok )
		XCTAssertNotNil( s.out.range( of: #"^Battery at \d{1,3}% \(.+ remaining\), \d+\.\d+V, smc charging (enabled|disabled)"#, options: .regularExpression ), s.out )
	}

	func testStatusCsvHasFiveFieldsAndAgreesWithStatus() {
		let c = csv()
		XCTAssertTrue( ( 1...100 ).contains( c.percent ) )
		XCTAssertTrue( [ "enabled", "disabled" ].contains( c.charging ) )
		XCTAssertTrue( [ "discharging", "not discharging" ].contains( c.discharging ) )
		XCTAssertTrue( CLI.battery( "status" ).out.contains( "smc charging \( c.charging )" ) )
	}

	func testPercentMatchesMacOSOwnReading() {
		let pmset = sh( "/usr/bin/pmset", [ "-g", "batt" ] ).out
		let match = pmset.range( of: #"(\d+)%"#, options: .regularExpression ).map { Int( pmset[ $0 ].dropLast() )! }
		let ours = csv().percent
		XCTAssertNotNil( match )
		XCTAssertLessThanOrEqual( abs( ours - ( match ?? -99 ) ), 1, "pmset says \( match ?? -1 ), battery says \( ours )" )
	}

	func testLogsReturnsRequestedTail() {
		CLI.battery( "status" )
		let log = CLI.battery( "logs", "5" ).out
		XCTAssertLessThanOrEqual( log.split( separator: "\n" ).count, 5 )
		XCTAssertFalse( log.isEmpty, "the helper log should have content" )
	}

	func testProbeReportsABackend() {
		XCTAssertTrue( CLI.battery( "probe" ).out.contains( "backend=" ) )
	}

	// MARK: Input validation (the helper must refuse, not just the parser)

	func testBadInputIsRefusedWithNonzeroExit() {
		let bad: [ [ String ] ] = [
			[ "bogus" ], [ "charge", "0" ], [ "charge", "101" ], [ "charge", "abc" ], [ "discharge", "4" ], [ "discharge", "101" ],
			[ "maintain" ], [ "maintain", "9" ], [ "maintain", "80-70" ], [ "maintain", "5-80" ], [ "maintain", "13.0V" ], [ "maintain", "11.4V", "5V" ],
			[ "schedule", "91" ], [ "schedule", "-1" ], [ "schedule" ], [ "charging", "maybe" ], [ "charging" ], [ "adapter", "1" ],
		]
		for args in bad {
			let r = CLI.battery( args )
			XCTAssertNotEqual( r.code, 0, "battery \( args.joined( separator: " " ) ) should fail, got: \( r.out )" )
			XCTAssertFalse( ( r.out + r.err ).isEmpty, "battery \( args.joined( separator: " " ) ) failed silently" )
		}
		XCTAssertEqual( csv().maintain, "", "refused commands must not leave a limit behind" )
	}

	// MARK: Charge limit

	func testMaintainSetsAndStopClearsTheLimit() {
		XCTAssertTrue( CLI.battery( "maintain", "80" ).ok )
		XCTAssertEqual( csv().maintain, "80" )
		XCTAssertTrue( CLI.battery( "status" ).out.contains( "maintained at 80%" ) )

		XCTAssertTrue( CLI.battery( "maintain", "stop" ).ok )
		XCTAssertEqual( csv().maintain, "" )
		XCTAssertTrue( csv().chargingEnabled, "stopping the limit must hand charging back" )
	}

	func testMaintainRangeIsStoredAsGiven() {
		XCTAssertTrue( CLI.battery( "maintain", "75-80" ).ok )
		XCTAssertEqual( csv().maintain, "75-80" )
		XCTAssertTrue( CLI.battery( "status" ).out.contains( "75% - 80%" ) )
	}

	func testMaintainVoltageBand() {
		XCTAssertTrue( CLI.battery( "maintain", "12.0V", "0.2V" ).ok )
		XCTAssertEqual( csv().maintain, "12V 0.2V" )
	}

	func testMaintainBelowCurrentLevelStopsCharging() throws {
		let start = csv()
		try XCTSkipUnless( start.percent >= 30, "battery too low to hold a limit under the level safely" )
		XCTAssertTrue( CLI.battery( "maintain", String( max( start.percent - 10, 20 ) ) ).ok )
		XCTAssertNotNil( eventually( 15 ) { csv().chargingEnabled ? nil : true }, "charging should be inhibited above the limit" )
	}

	func testChangingTheLimitReplacesTheOldOne() {
		CLI.battery( "maintain", "80" )
		CLI.battery( "maintain", "70-75" )
		XCTAssertEqual( csv().maintain, "70-75" )
	}

	func testForceDischargeRunsOnBatteryWhenAboveLimit() throws {
		try XCTSkipUnless( Self.canCutAdapter, "this Mac cannot cut the adapter" )
		let c = csv()
		try XCTSkipUnless( c.percent >= 35 && c.percent > 30, "needs charge above the limit under test" )
		XCTAssertTrue( CLI.battery( "maintain", "25-30", "--force-discharge" ).ok )
		if Self.lidClosed {
			// Clamshell needs the adapter: charging is held, the adapter stays on
			XCTAssertNil( eventually( 20 ) { csv().discharging == "discharging" ? true : nil }, "lid closed: force-discharge must not cut the adapter" )
			XCTAssertFalse( csv().chargingEnabled, "charging is still held off above the limit" )
			CLI.battery( "maintain", "stop" )
			return
		}
		XCTAssertNotNil( eventually( 20 ) { csv().discharging == "discharging" ? true : nil }, "force-discharge should switch to battery power while above the limit" )
		CLI.battery( "maintain", "stop" )
		XCTAssertNotNil( eventually( 20 ) { csv().discharging == "not discharging" ? true : nil }, "stopping must put the adapter back" )
	}

	func testLimitPersistsToDisk() {
		CLI.battery( "maintain", "80" )
		XCTAssertEqual( try? String( contentsOfFile: "/var/db/co.palokaj.battery/maintain", encoding: .utf8 ).trimmingCharacters( in: .whitespacesAndNewlines ).split( separator: " " ).first.map( String.init ), "80" )
		CLI.battery( "maintain", "stop" )
		XCTAssertFalse( FileManager.default.fileExists( atPath: "/var/db/co.palokaj.battery/maintain" ), "stop must delete the persisted target or a reboot resurrects it" )
	}

	// MARK: Charging and adapter switches

	func testChargingOffAndOn() {
		XCTAssertTrue( CLI.battery( "charging", "off" ).ok )
		XCTAssertEqual( csv().charging, "disabled" )
		XCTAssertTrue( CLI.battery( "charging", "on" ).ok )
		XCTAssertEqual( csv().charging, "enabled" )
	}

	func testAdapterOffAndOn() throws {
		try XCTSkipUnless( Self.canCutAdapter, "this Mac cannot cut the adapter" )
		XCTAssertTrue( CLI.battery( "adapter", "off" ).ok )
		XCTAssertNotNil( eventually( 15 ) { csv().discharging == "discharging" ? true : nil } )
		XCTAssertTrue( CLI.battery( "adapter", "on" ).ok )
		XCTAssertNotNil( eventually( 15 ) { csv().discharging == "not discharging" ? true : nil } )
	}

	func testRecoverUndoesEverything() {
		CLI.battery( "maintain", "80" )
		CLI.battery( "charging", "off" )
		CLI.battery( "schedule", "30" )
		XCTAssertTrue( CLI.battery( "maintain", "recover" ).ok )
		let c = csv()
		XCTAssertEqual( c.maintain, "" )
		XCTAssertTrue( c.chargingEnabled )
		XCTAssertEqual( c.discharging, "not discharging" )
	}

	// MARK: Jobs

	func testChargeJobStartsReportsAndCancels() {
		XCTAssertTrue( CLI.battery( "charge", "100" ).ok )
		let s = CLI.battery( "status" ).out
		XCTAssertTrue( s.contains( "harging to 100%" ) || s.contains( "100%" ), s )
		XCTAssertTrue( CLI.battery( "maintain", "recover" ).ok )
		XCTAssertFalse( CLI.battery( "status" ).out.contains( "Charging to" ), "recover must cancel the job" )
	}

	func testDischargeJobStartsAndCancels() throws {
		try XCTSkipUnless( Self.canCutAdapter, "this Mac cannot cut the adapter" )
		let c = csv()
		try XCTSkipUnless( c.percent > 40, "battery too low" )
		XCTAssertTrue( CLI.battery( "discharge", String( c.percent - 5 ) ).ok )
		XCTAssertTrue( CLI.battery( "status" ).out.contains( "ischarging to" ) )
		CLI.battery( "maintain", "recover" )
		XCTAssertNotNil( eventually( 20 ) { csv().discharging == "not discharging" ? true : nil } )
	}

	func testCalibrateStartsAndCancels() throws {
		try XCTSkipUnless( Self.canCutAdapter, "calibration needs adapter control" )
		let c = csv()
		try XCTSkipUnless( c.percent >= 20, "calibration starts with a discharge, needs charge" )
		XCTAssertTrue( CLI.battery( "calibrate" ).ok )
		XCTAssertTrue( CLI.battery( "status" ).out.lowercased().contains( "calibrat" ) )
		XCTAssertTrue( CLI.battery( "maintain", "recover" ).ok )
		XCTAssertFalse( CLI.battery( "status" ).out.lowercased().contains( "calibrat" ) )
		XCTAssertNotNil( eventually( 20 ) { csv().discharging == "not discharging" ? true : nil } )
	}

	// MARK: Schedule

	func testScheduleOnAndOffPersists() {
		func days() -> String? { try? String( contentsOfFile: "/var/db/co.palokaj.battery/schedule", encoding: .utf8 ).split( separator: " " ).first.map( String.init ) }
		XCTAssertTrue( CLI.battery( "schedule", "30" ).ok )
		XCTAssertEqual( days(), "30" )
		XCTAssertTrue( CLI.battery( "schedule", "0" ).ok )
		XCTAssertEqual( days(), "0" )
	}

	// MARK: Robustness

	func testConcurrentClientsAllGetAnswers() {
		let group = DispatchGroup()
		var codes = [ Int32 ]( repeating: -1, count: 8 )
		let lock = NSLock()
		for i in 0..<8 {
			group.enter()
			DispatchQueue.global().async {
				let r = CLI.battery( i % 2 == 0 ? "status" : "status_csv" )
				lock.lock(); codes[ i ] = r.code; lock.unlock()
				group.leave()
			}
		}
		XCTAssertEqual( group.wait( timeout: .now() + 60 ), .success )
		XCTAssertEqual( codes, [ Int32 ]( repeating: 0, count: 8 ) )
	}

}
