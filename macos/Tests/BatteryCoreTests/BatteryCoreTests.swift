import XCTest
@testable import BatteryCore

final class MaintainTargetTests: XCTestCase {

	func testParsesSingleLevel() throws {
		XCTAssertEqual( try MaintainTarget( parsing: "80" ), .level( lower: 80, upper: 80 ) )
		XCTAssertEqual( try MaintainTarget( parsing: "0" ), .level( lower: 0, upper: 0 ) )
	}

	func testParsesRange() throws {
		XCTAssertEqual( try MaintainTarget( parsing: "70-80" ), .level( lower: 70, upper: 80 ) )
	}

	func testRejectsBadRanges() {
		for bad in [ "80-70", "80-80", "5-50", "10-101", "a-b", "70-", "-80", "101", "x" ] {
			XCTAssertThrowsError( try MaintainTarget( parsing: bad ), bad )
		}
	}

	func testParsesVoltage() throws {
		XCTAssertEqual( try MaintainTarget( parsing: "11.4V" ), .voltage( center: 11.4, hysteresis: 0.1 ) )
		XCTAssertEqual( try MaintainTarget( parsing: "11.4V", hysteresis: "0.3V" ), .voltage( center: 11.4, hysteresis: 0.3 ) )
	}

	func testRejectsOutOfBoundsVoltage() {
		XCTAssertThrowsError( try MaintainTarget( parsing: "10.4V" ) )
		XCTAssertThrowsError( try MaintainTarget( parsing: "12.7V" ) )
		XCTAssertThrowsError( try MaintainTarget( parsing: "11.4V", hysteresis: "0.05V" ) )
		XCTAssertThrowsError( try MaintainTarget( parsing: "11.4V", hysteresis: "2.1V" ) )
		XCTAssertThrowsError( try MaintainTarget( parsing: "11.4V", hysteresis: "0.3" ) )
	}

	func testPersistRoundTrip() throws {
		for s in [ "80", "70-80", "11.4V 0.1V", "12V 0.3V" ] {
			XCTAssertEqual( try MaintainTarget( persisted: s ).persisted, s )
		}
	}

	func testDisplay() throws {
		XCTAssertEqual( try MaintainTarget( parsing: "80" ).display, "80%" )
		XCTAssertEqual( try MaintainTarget( parsing: "70-80" ).display, "70% - 80%" )
		XCTAssertEqual( try MaintainTarget( parsing: "11.4V" ).display, "11.4V ±0.1V" )
	}

}

final class ControllerTests: XCTestCase {

	private func state( _ pct: Int, charging: Bool?, ac: Bool = true, v: Double? = nil ) -> BatteryState {
		BatteryState( percent: pct, voltage: v, chargingEnabled: charging, acAttached: ac )
	}

	func testStopsAtUpper() {
		let d = Controller.decide( .level( lower: 80, upper: 80 ), state( 80, charging: true ) )
		XCTAssertEqual( d, Decision( action: .disableCharging, led: .green ) )
	}

	func testKeepsLedGreenWhenAlreadyOffOnAC() {
		let d = Controller.decide( .level( lower: 70, upper: 80 ), state( 85, charging: false ) )
		XCTAssertEqual( d, Decision( action: .none, led: .green ) )
	}

	func testIdleAboveUpperOnBattery() {
		XCTAssertEqual( Controller.decide( .level( lower: 70, upper: 80 ), state( 85, charging: false, ac: false ) ), .idle )
	}

	func testResumesBelowLower() {
		let d = Controller.decide( .level( lower: 70, upper: 80 ), state( 69, charging: false ) )
		XCTAssertEqual( d, Decision( action: .enableCharging, led: .orange ) )
	}

	func testHysteresisInsideBandDoesNothing() {
		XCTAssertEqual( Controller.decide( .level( lower: 70, upper: 80 ), state( 75, charging: false ) ), .idle )
		XCTAssertEqual( Controller.decide( .level( lower: 70, upper: 80 ), state( 75, charging: true ) ), .idle )
	}

	func testUnknownChargingStateNeverResumes() {
		XCTAssertEqual( Controller.decide( .level( lower: 70, upper: 80 ), state( 10, charging: nil ) ), .idle )
	}

	func testVoltage() {
		let t = MaintainTarget.voltage( center: 11.4, hysteresis: 0.1 )
		XCTAssertEqual( Controller.decide( t, state( 50, charging: false, v: 11.2 ) ).action, .enableCharging )
		XCTAssertEqual( Controller.decide( t, state( 50, charging: true, v: 11.5 ) ).action, .disableCharging )
		XCTAssertEqual( Controller.decide( t, state( 50, charging: true, v: 11.4 ) ).action, .none )
		XCTAssertEqual( Controller.decide( t, state( 50, charging: true, v: nil ) ).action, .none )
	}

	func testPollInterval() {
		XCTAssertEqual( Controller.chargePollInterval( percent: 70, target: 80 ), 60 )
		XCTAssertEqual( Controller.chargePollInterval( percent: 77, target: 80 ), 20 )
	}

}

final class SMCPlanTests: XCTestCase {

	func testTahoe() {
		let caps = SMCCapabilities( keys: [ "CHTE", "CH0B", "CHIE" ] )
		XCTAssertEqual( SMCPlan.charging( false, caps ), [ SMCWrite( "CHTE", "01000000" ) ] )
		XCTAssertEqual( SMCPlan.charging( true, caps ), [ SMCWrite( "CHTE", "00000000" ) ] )
		XCTAssertEqual( SMCPlan.adapter( on: false, caps ), [ SMCWrite( "CHIE", "08" ) ] )
		XCTAssertEqual( SMCPlan.adapter( on: true, caps ), [ SMCWrite( "CHIE", "00" ) ] )
	}

	func testLegacy() {
		let caps = SMCCapabilities( keys: [ "CH0B", "CH0C", "CH0I" ] )
		XCTAssertEqual( SMCPlan.charging( false, caps ), [ SMCWrite( "CH0B", "02" ), SMCWrite( "CH0C", "02" ) ] )
		XCTAssertEqual( SMCPlan.charging( true, caps ), [ SMCWrite( "CH0B", "00" ), SMCWrite( "CH0C", "00" ) ] )
		XCTAssertEqual( SMCPlan.adapter( on: false, caps ), [ SMCWrite( "CH0I", "01" ) ] )
	}

	func testCH0JPreferredOverCH0I() {
		let caps = SMCCapabilities( keys: [ "CH0B", "CH0I", "CH0J" ] )
		XCTAssertEqual( SMCPlan.adapter( on: false, caps ), [ SMCWrite( "CH0J", "01" ) ] )
	}

	func testUnknownHardware() {
		XCTAssertNil( SMCPlan.charging( false, SMCCapabilities( keys: [] ) ) )
	}

	func testReadSide() {
		let tahoe = SMCCapabilities( keys: [ "CHTE", "CHIE" ] )
		XCTAssertEqual( SMCPlan.chargingEnabled( tahoe ) { _ in "00000000" }, true )
		XCTAssertEqual( SMCPlan.chargingEnabled( tahoe ) { _ in "01000000" }, false )
		XCTAssertNil( SMCPlan.chargingEnabled( tahoe ) { _ in nil } )

		let legacy = SMCCapabilities( keys: [ "CH0B", "CH0I" ] )
		XCTAssertEqual( SMCPlan.chargingEnabled( legacy ) { _ in "00" }, true )
		XCTAssertEqual( SMCPlan.chargingEnabled( legacy ) { _ in "02" }, false )
		XCTAssertEqual( SMCPlan.discharging( legacy ) { _ in "00" }, false )
		XCTAssertEqual( SMCPlan.discharging( legacy ) { _ in "01" }, true )
	}

	func testLed() {
		XCTAssertEqual( SMCPlan.led( .green ), SMCWrite( "ACLC", "03" ) )
		XCTAssertEqual( SMCPlan.led( .orange ), SMCWrite( "ACLC", "04" ) )
		XCTAssertEqual( SMCPlan.led( .off ), SMCWrite( "ACLC", "00" ) )
	}

}

final class CalibrationTests: XCTestCase {

	func testFullCycle() {
		var c = Calibration()
		let t0 = Date( timeIntervalSince1970: 0 )

		XCTAssertFalse( c.advance( percent: 40, now: t0 ) )
		XCTAssertTrue( c.advance( percent: 15, now: t0 ) )
		XCTAssertEqual( c.phase, .charging100 )

		XCTAssertFalse( c.advance( percent: 99, now: t0 ) )
		XCTAssertTrue( c.advance( percent: 100, now: t0 ) )
		XCTAssertEqual( c.phase, .holding )

		XCTAssertFalse( c.advance( percent: 100, now: t0.addingTimeInterval( 3599 ) ) )
		XCTAssertTrue( c.advance( percent: 100, now: t0.addingTimeInterval( 3600 ) ) )
		XCTAssertEqual( c.phase, .discharging80 )

		XCTAssertFalse( c.advance( percent: 90, now: t0 ) )
		XCTAssertTrue( c.advance( percent: 80, now: t0 ) )
		XCTAssertEqual( c.phase, .done )
		XCTAssertFalse( c.advance( percent: 10, now: t0 ) )
	}

}

final class CommandTests: XCTestCase {

	private func parse( _ s: String ) throws -> Command {
		try Command( arguments: s.split( separator: " " ).map( String.init ) )
	}

	func testSimple() throws {
		XCTAssertEqual( try parse( "" ), .help )
		XCTAssertEqual( try parse( "status" ), .status )
		XCTAssertEqual( try parse( "status_csv" ), .statusCSV )
		XCTAssertEqual( try parse( "--version" ), .version )
		XCTAssertEqual( try parse( "calibrate" ), .calibrate )
		XCTAssertEqual( try parse( "logs" ), .logs( lines: 100 ) )
		XCTAssertEqual( try parse( "logs 5" ), .logs( lines: 5 ) )
	}

	func testOnOff() throws {
		XCTAssertEqual( try parse( "charging off" ), .charging( on: false ) )
		XCTAssertEqual( try parse( "adapter on" ), .adapter( on: true ) )
		XCTAssertThrowsError( try parse( "charging maybe" ) )
		XCTAssertThrowsError( try parse( "adapter" ) )
	}

	func testChargeDischarge() throws {
		XCTAssertEqual( try parse( "charge 90" ), .charge( 90 ) )
		XCTAssertEqual( try parse( "discharge 0" ), .discharge( 0 ) )
		XCTAssertThrowsError( try parse( "charge 101" ) )
		XCTAssertThrowsError( try parse( "charge" ) )
	}

	func testMaintain() throws {
		XCTAssertEqual( try parse( "maintain stop" ), .maintain( .stop ) )
		XCTAssertEqual( try parse( "maintain recover" ), .maintain( .recover ) )
		XCTAssertEqual( try parse( "maintain 80" ), .maintain( .set( .level( lower: 80, upper: 80 ), forceDischarge: false ) ) )
		XCTAssertEqual( try parse( "maintain 70-80 --force-discharge" ), .maintain( .set( .level( lower: 70, upper: 80 ), forceDischarge: true ) ) )
		XCTAssertEqual( try parse( "maintain 11.4V 0.3V" ), .maintain( .set( .voltage( center: 11.4, hysteresis: 0.3 ), forceDischarge: false ) ) )
		XCTAssertEqual( try parse( "maintain 11.4V 0.3V --force-discharge" ), .maintain( .set( .voltage( center: 11.4, hysteresis: 0.3 ), forceDischarge: true ) ) )
		XCTAssertThrowsError( try parse( "maintain" ) )
		XCTAssertThrowsError( try parse( "maintain banana" ) )
	}

	func testUnknownAndDroppedCommands() {
		XCTAssertThrowsError( try parse( "visudo" ) )
		XCTAssertThrowsError( try parse( "update_silent" ) )
		XCTAssertThrowsError( try parse( "wat" ) )
	}

}

final class FormattingTests: XCTestCase {

	let sample = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=23855203)\t100%; charged; 0:00 remaining present: true\n"

	func testPmsetParsing() {
		let p = PowerSnapshot( pmset: sample )
		XCTAssertEqual( p, PowerSnapshot( percent: 100, remaining: "0:00", acAttached: true ) )
	}

	func testPmsetOnBatteryNoEstimate() {
		let out = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t57%; discharging; (no estimate) present: true\n"
		XCTAssertEqual( PowerSnapshot( pmset: out ), PowerSnapshot( percent: 57, remaining: "no estimate", acAttached: false ) )
	}

	func testPmsetWithoutBattery() {
		XCTAssertNil( PowerSnapshot( pmset: "Now drawing from 'AC Power'\n" ) )
	}

	func testStatus() {
		let p = PowerSnapshot( percent: 80, remaining: "1:23", acAttached: true )
		XCTAssertEqual( Report.status( p, voltage: 12.345, charging: true, maintain: nil ),
			"Battery at 80% (1:23 remaining), 12.345V, smc charging enabled" )
		XCTAssertEqual( Report.status( p, voltage: 12.3, charging: false, maintain: .level( lower: 70, upper: 80 ) ),
			"Battery at 80% (1:23 remaining), 12.3V, smc charging disabled\nYour battery is currently being maintained at 70% - 80%" )
	}

	func testCSV() {
		let p = PowerSnapshot( percent: 80, remaining: "1:23", acAttached: true )
		XCTAssertEqual( Report.csv( p, charging: true, discharging: false, maintain: .level( lower: 80, upper: 80 ) ),
			"80,1:23,enabled,not discharging,80" )
		XCTAssertEqual( Report.csv( p, charging: nil, discharging: nil, maintain: nil ), "80,1:23,unknown,unknown," )
	}

}
