import XCTest
@testable import BatteryCore

final class MaintainTargetTests: XCTestCase {

	func testParsesSingleLevel() throws {
		XCTAssertEqual( try MaintainTarget( parsing: "80" ), .level( lower: 80, upper: 80 ) )
		XCTAssertThrowsError( try MaintainTarget( parsing: "0" ) )   // would drain with force-discharge
		XCTAssertThrowsError( try MaintainTarget( parsing: "9" ) )
		XCTAssertEqual( try MaintainTarget( parsing: "10" ), .level( lower: 10, upper: 10 ) )
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
		XCTAssertEqual( d, Decision( action: .disableCharging, led: .green, refilling: false ) )
	}

	func testKeepsLedGreenWhenAlreadyOffOnAC() {
		let d = Controller.decide( .level( lower: 70, upper: 80 ), state( 85, charging: false ) )
		XCTAssertEqual( d, Decision( action: .none, led: .green, refilling: false ) )
	}

	func testIdleAboveUpperOnBattery() {
		XCTAssertEqual( Controller.decide( .level( lower: 70, upper: 80 ), state( 85, charging: false, ac: false ) ), .idle )
	}

	func testResumesBelowLower() {
		let d = Controller.decide( .level( lower: 70, upper: 80 ), state( 69, charging: false ) )
		XCTAssertEqual( d, Decision( action: .enableCharging, led: .orange, refilling: true ) )
	}

	func testHysteresisInsideBandDoesNothing() {
		XCTAssertEqual( Controller.decide( .level( lower: 70, upper: 80 ), state( 75, charging: false ) ), .idle )
		// Refilling from below lower: keep going up to upper
		var refilling = state( 75, charging: true ); refilling.refilling = true
		XCTAssertEqual( Controller.decide( .level( lower: 70, upper: 80 ), refilling ), .idle )
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
		XCTAssertThrowsError( try parse( "discharge 0" ) )
		XCTAssertThrowsError( try parse( "discharge 4" ) )
		XCTAssertEqual( try parse( "discharge 5" ), .discharge( 5 ) )
		XCTAssertThrowsError( try parse( "charge 0" ) )
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

final class BatteryStatusTests: XCTestCase {

	func testJSONRoundTrip() {
		let s = BatteryStatus( percent: 81, voltage: 12.4, remaining: "1:05", acAttached: true, chargingEnabled: false,
		                       maintain: "70-80", forceDischarge: true, smcKeys: [ "CHTE", "CHIE" ], daemonVersion: "2.0.0" )
		XCTAssertEqual( BatteryStatus.decode( s.encoded() ), s )
	}

	func testHeadline() {
		XCTAssertEqual( BatteryStatus( percent: 50, acAttached: false ).headline, "On battery" )
		XCTAssertEqual( BatteryStatus( percent: 50, acAttached: true, chargingEnabled: true ).headline, "Charging" )
		XCTAssertEqual( BatteryStatus( percent: 80, acAttached: true, chargingEnabled: false, maintain: "80" ).headline, "Holding at limit" )
		XCTAssertEqual( BatteryStatus( percent: 100, acAttached: true ).headline, "Fully charged" )
		XCTAssertEqual( BatteryStatus( percent: 100, acAttached: true, chargingEnabled: false, maintain: "80" ).headline, "Holding at limit" )
		XCTAssertEqual( BatteryStatus( percent: 60, acAttached: true, discharging: true ).headline, "Discharging on adapter" )
		XCTAssertEqual( BatteryStatus( percent: 60, acAttached: true, activity: "Charging to 90%" ).headline, "Charging to 90%" )
	}

	func testMaintainTargetParse() {
		XCTAssertEqual( BatteryStatus( percent: 1, acAttached: true, maintain: "70-80" ).maintainTarget, .level( lower: 70, upper: 80 ) )
		XCTAssertNil( BatteryStatus( percent: 1, acAttached: true ).maintainTarget )
	}

}


// MARK: #475 range semantics + backends

final class RangeAndBackendTests: XCTestCase {

	private func st( _ p: Int, charging: Bool?, ac: Bool = true, refilling: Bool = false ) -> BatteryState {
		BatteryState( percent: p, chargingEnabled: charging, acAttached: ac, refilling: refilling )
	}

	func testPluggedInInsideBandHolds() {
		// #475: maintain 45-55 at 52% plugged in must NOT charge up to 55
		let d = Controller.decide( .level( lower: 45, upper: 55 ), st( 52, charging: true ) )
		XCTAssertEqual( d.action, .disableCharging )
	}

	func testBelowLowerStartsRefill() {
		let held = Controller.decide( .level( lower: 45, upper: 55 ), st( 44, charging: false ) )
		XCTAssertEqual( held.action, .enableCharging )
		XCTAssertEqual( held.refilling, true )
		let already = Controller.decide( .level( lower: 45, upper: 55 ), st( 44, charging: true ) )
		XCTAssertEqual( already.action, .none )
		XCTAssertEqual( already.refilling, true )
	}

	func testRefillStopsAtUpperAndClearsLatch() {
		let d = Controller.decide( .level( lower: 45, upper: 55 ), st( 55, charging: true, refilling: true ) )
		XCTAssertEqual( d.action, .disableCharging )
		XCTAssertEqual( d.refilling, false )
	}

	func testSingleValueNeverHoldsInBand() {
		// lower == upper has no band: below N charge, at N stop
		XCTAssertEqual( Controller.decide( .level( lower: 80, upper: 80 ), st( 79, charging: false ) ).action, .enableCharging )
		XCTAssertEqual( Controller.decide( .level( lower: 80, upper: 80 ), st( 79, charging: true ) ).action, .none )
	}

	// Real key sets from issue reports
	private func caps( _ keys: [ String ] ) -> SMCCapabilities { SMCCapabilities( keys: Set( keys ) ) }

	func testBackendFixtures() {
		XCTAssertEqual( caps( [ "CH0B", "CH0C", "CH0I" ] ).backend, .legacy )
		XCTAssertEqual( caps( [ "CHTE", "CHIE", "CH0J" ] ).backend, .tahoe )                       // M4 Air 26.3
		XCTAssertEqual( caps( [ "bfD0", "bfE0", "bfF0", "CHIE", "CH0J" ] ).backend, .firmwareLimit ) // M4 Pro 15.8.2
		XCTAssertEqual( caps( [ "CHIE" ] ).backend, .softwareCut )                                   // M4 Air 27.0 (bf* gated)
		XCTAssertEqual( caps( [ "CH0J" ] ).backend, .softwareCut )                                   // M1 Pro 27.0
		XCTAssertEqual( caps( [] ).backend, .none )
		XCTAssertEqual( caps( [ "bfD0", "bfF0" ] ).backend, .none )                                  // partial bf* set is unusable
	}

	func testLE32() {
		XCTAssertEqual( SMCPlan.le32( 80 ), "50000000" )
		XCTAssertEqual( SMCPlan.le32( 78 ), "4e000000" )
		XCTAssertEqual( SMCPlan.le32( 300 ), "2c010000" )
	}

	func testFirmwareWriteOrder() {
		let w = SMCPlan.firmwareLimit( upper: 80, lower: 80 )!
		XCTAssertEqual( w.map( \.key ), [ "bfF0", "bfD0", "bfE0", "bfF0" ] )
		XCTAssertEqual( w.map( \.hex ), [ "00", "50000000", "4e000000", "02" ] )   // single N resumes at N-2
		XCTAssertEqual( SMCPlan.firmwareLimit( upper: 80, lower: 70 )!.map( \.hex )[ 2 ], "46000000" )
	}

	func testFirmwareSafetyFloorAndNoLimit() {
		XCTAssertNil( SMCPlan.firmwareLimit( upper: 15, lower: 10 ) )   // would drain on purpose
		XCTAssertNil( SMCPlan.firmwareLimit( upper: 100, lower: 95 ) )  // 100 = no limit
		XCTAssertEqual( SMCPlan.firmwareReset.map( \.hex ), [ "00", "00000000", "00000000" ] )
	}

	func testFirmwareHoldFreezesAtCurrentLevel() {
		let c = caps( [ "bfD0", "bfE0", "bfF0" ] )
		XCTAssertEqual( SMCPlan.charging( false, c, level: 64 )!.map( \.hex )[ 1 ], "40000000" )
		XCTAssertNil( SMCPlan.charging( false, c ) )                    // level unknown: refuse
		XCTAssertEqual( SMCPlan.charging( false, c, level: 100 ), [] )  // nothing to hold
		XCTAssertEqual( SMCPlan.charging( true, c ), SMCPlan.firmwareReset )
	}

	func testSoftwareCutUsesAdapterKeys() {
		XCTAssertEqual( SMCPlan.charging( false, caps( [ "CHIE" ] ) ), [ SMCWrite( "CHIE", "08" ) ] )
		XCTAssertEqual( SMCPlan.charging( true, caps( [ "CHIE" ] ) ), [ SMCWrite( "CHIE", "00" ) ] )
		XCTAssertNil( SMCPlan.charging( false, caps( [] ) ) )
	}

	func testFirmwareChargingRead() {
		let c = caps( [ "bfD0", "bfE0", "bfF0" ] )
		XCTAssertEqual( SMCPlan.chargingEnabled( c ) { $0 == "bfF0" ? "02" : nil }, false )
		XCTAssertEqual( SMCPlan.chargingEnabled( c ) { $0 == "bfF0" ? "00" : nil }, true )
	}

}


final class ScheduleCommandTests: XCTestCase {
	func testSchedule() throws {
		XCTAssertEqual( try Command( arguments: [ "schedule", "30" ] ), .schedule( days: 30 ) )
		XCTAssertEqual( try Command( arguments: [ "schedule", "0" ] ), .schedule( days: 0 ) )
		XCTAssertThrowsError( try Command( arguments: [ "schedule", "400" ] ) )
		XCTAssertThrowsError( try Command( arguments: [ "schedule" ] ) )
	}
}


final class LimitsTests: XCTestCase {

	func testChargeAndDischargeBounds() {
		XCTAssertNil( Limits.check( charge: 100 ) )
		XCTAssertNotNil( Limits.check( charge: 0 ) )
		XCTAssertNotNil( Limits.check( charge: 101 ) )
		XCTAssertNil( Limits.check( discharge: 5 ) )
		XCTAssertNotNil( Limits.check( discharge: -1 ) )   // a hostile client: never reaches its goal, runs flat
		XCTAssertNotNil( Limits.check( discharge: 4 ) )
	}

	func testMaintainBoundsEvenForHandBuiltTargets() {
		XCTAssertNil( Limits.check( maintain: .level( lower: 80, upper: 80 ) ) )
		XCTAssertNotNil( Limits.check( maintain: .level( lower: 0, upper: 0 ) ) )
		XCTAssertNotNil( Limits.check( maintain: .level( lower: 5, upper: 50 ) ) )
		XCTAssertNotNil( Limits.check( maintain: .level( lower: 60, upper: 50 ) ) )
		XCTAssertNotNil( Limits.check( maintain: .voltage( center: 30, hysteresis: 0.1 ) ) )
	}

}

final class StatusRenderingTests: XCTestCase {

	func testStatusFromSnapshot() {
		let s = BatteryStatus( percent: 81, voltage: 12.4, remaining: "1:05", acAttached: true, chargingEnabled: false, maintain: "70-80", activity: "Charging to 90%", warning: "x" )
		let text = Report.status( s )
		XCTAssertTrue( text.hasPrefix( "Battery at 81% (1:05 remaining), 12.4V, smc charging disabled" ) )
		XCTAssertTrue( text.contains( "maintained at 70% - 80%" ) )
		XCTAssertTrue( text.contains( "Charging to 90%" ) )
		XCTAssertTrue( text.contains( "Warning: x" ) )
	}

	func testCSVFromSnapshot() {
		let s = BatteryStatus( percent: 50, remaining: "no estimate", acAttached: true, chargingEnabled: true, discharging: false, maintain: "80" )
		XCTAssertEqual( Report.csv( s ), "50,no estimate,enabled,not discharging,80" )
	}

}

// MARK: Refactor extractions

final class JobPlannerTests: XCTestCase {

	private let t0 = Date( timeIntervalSince1970: 1_000_000 )

	func testChargeBelowHundredHoldsAtReachedLevel() {
		XCTAssertEqual( JobPlanner.start( .charge( 90 ) ), [ .adapter( on: true ), .charging( on: true, holdAtLevel: nil ) ] )
		XCTAssertFalse( JobPlanner.step( .charge( 90 ), percent: 89, now: t0 ).finished )
		let done = JobPlanner.step( .charge( 90 ), percent: 91, now: t0 )
		XCTAssertTrue( done.finished )
		XCTAssertEqual( done.intents, [ .charging( on: false, holdAtLevel: 91 ) ] )
	}

	func testChargeToHundredLeavesChargingNormal() {
		// the bug: holding charging off at 100% with no limit set meant the Mac never charged again
		XCTAssertEqual( JobPlanner.step( .charge( 100 ), percent: 100, now: t0 ).intents, [ .charging( on: true, holdAtLevel: nil ) ] )
	}

	func testDischargeRestoresAdapterAtTarget() {
		XCTAssertEqual( JobPlanner.start( .discharge( 50 ) ), [ .adapter( on: false ) ] )
		XCTAssertFalse( JobPlanner.step( .discharge( 50 ), percent: 51, now: t0 ).finished )
		let done = JobPlanner.step( .discharge( 50 ), percent: 50, now: t0 )
		XCTAssertEqual( done.intents, [ .adapter( on: true ) ] )
		XCTAssertTrue( done.finished )
	}

	func testCalibrationWalksThroughPhases() {
		var job = Job.calibrate( Calibration() )
		XCTAssertEqual( JobPlanner.start( job ), [ .adapter( on: false ) ] )

		var s = JobPlanner.step( job, percent: 15, now: t0 )          // -> charging100
		XCTAssertEqual( s.intents, [ .adapter( on: true ), .charging( on: true, holdAtLevel: nil ) ] )
		job = s.job
		s = JobPlanner.step( job, percent: 100, now: t0 )              // -> holding
		job = s.job
		XCTAssertFalse( s.finished )
		s = JobPlanner.step( job, percent: 100, now: t0.addingTimeInterval( 3601 ) )   // -> discharging80
		XCTAssertEqual( s.intents, [ .adapter( on: false ) ] )
		job = s.job
		s = JobPlanner.step( job, percent: 80, now: t0.addingTimeInterval( 4000 ) )    // -> done
		XCTAssertTrue( s.finished )
		XCTAssertEqual( s.intents, [ .adapter( on: true ), .charging( on: true, holdAtLevel: nil ) ] )
	}

	func testActivityText() {
		XCTAssertEqual( Job.charge( 90 ).activity, "Charging to 90%" )
		XCTAssertEqual( Job.discharge( 50 ).activity, "Discharging to 50%" )
	}

}

final class ScheduleTests: XCTestCase {

	private let t0 = Date( timeIntervalSince1970: 1_000_000 )
	private let day = 86400.0

	func testEnablingCountsFromNow() {
		var s = Schedule()
		XCTAssertNil( s.nextRun )
		s.set( days: 7, now: t0 )
		XCTAssertEqual( s.nextRun, t0.addingTimeInterval( 7 * day ) )
	}

	func testReEnablingAfterOffDoesNotFireImmediately() {
		var s = Schedule( days: 7, lastRun: t0 )
		s.set( days: 0, now: t0.addingTimeInterval( 30 * day ) )
		s.set( days: 7, now: t0.addingTimeInterval( 60 * day ) )
		XCTAssertFalse( s.isDue( now: t0.addingTimeInterval( 61 * day ), acAttached: true, busy: false ) )
	}

	func testDueNeedsACAndIdle() {
		let s = Schedule( days: 1, lastRun: t0 )
		let later = t0.addingTimeInterval( 2 * day )
		XCTAssertTrue( s.isDue( now: later, acAttached: true, busy: false ) )
		XCTAssertFalse( s.isDue( now: later, acAttached: false, busy: false ) )
		XCTAssertFalse( s.isDue( now: later, acAttached: true, busy: true ) )
		XCTAssertFalse( s.isDue( now: t0.addingTimeInterval( day / 2 ), acAttached: true, busy: false ) )
	}

	func testClampAndPersistence() {
		XCTAssertEqual( Schedule( days: 500 ).days, 90 )
		XCTAssertEqual( Schedule( days: -3 ).days, 0 )
		let s = Schedule( days: 30, lastRun: t0 )
		XCTAssertEqual( Schedule( persisted: s.persisted ), s )
		XCTAssertNil( Schedule( persisted: "7 0" ).lastRun )     // 0 = never
		XCTAssertEqual( Schedule( persisted: "garbage" ).days, 0 )
	}

}

final class MaintainValidationTests: XCTestCase {

	private func caps( _ k: [ String ] ) -> SMCCapabilities { SMCCapabilities( keys: Set( k ) ) }

	func testUnsupportedMac() {
		XCTAssertNotNil( Limits.check( maintain: .level( lower: 80, upper: 80 ), force: false, caps: caps( [] ) ) )
	}

	func testFirmwareRules() {
		let fw = caps( [ "bfD0", "bfE0", "bfF0" ] )
		XCTAssertNil( Limits.check( maintain: .level( lower: 70, upper: 80 ), force: false, caps: fw ) )
		XCTAssertNotNil( Limits.check( maintain: .voltage( center: 11.4, hysteresis: 0.1 ), force: false, caps: fw ) )
		XCTAssertNotNil( Limits.check( maintain: .level( lower: 80, upper: 80 ), force: true, caps: fw ) )   // no adapter-cut key
	}

	func testForceNeedsAdapterKey() {
		XCTAssertNil( Limits.check( maintain: .level( lower: 80, upper: 80 ), force: true, caps: caps( [ "CHTE", "CHIE" ] ) ) )
		XCTAssertNotNil( Limits.check( maintain: .level( lower: 80, upper: 80 ), force: true, caps: caps( [ "CHTE" ] ) ) )
	}

	func testPersistedLineRoundTrip() throws {
		let t = MaintainTarget.level( lower: 70, upper: 80 )
		XCTAssertEqual( MaintainTarget.parseLine( t.persistedLine( force: true ) )?.force, true )
		XCTAssertEqual( MaintainTarget.parseLine( t.persistedLine( force: false ) )?.target, t )
		XCTAssertEqual( MaintainTarget.parseLine( "11.4V 0.3V --force-discharge" )?.target, .voltage( center: 11.4, hysteresis: 0.3 ) )
		XCTAssertNil( MaintainTarget.parseLine( "junk" ) )
	}

}

final class ControllerExtrasTests: XCTestCase {

	func testForceDischargeDoesNotFlapWhenAdapterCutMakesACReadFalse() {
		// cut adapter => macOS says "not on AC". Without `currentlyCut` the loop would restore and re-cut every tick.
		XCTAssertTrue( Controller.forceDischargeCut( percent: 85, upper: 80, acAttached: false, currentlyCut: true ) )
		XCTAssertFalse( Controller.forceDischargeCut( percent: 85, upper: 80, acAttached: false, currentlyCut: false ) )
		XCTAssertFalse( Controller.forceDischargeCut( percent: 80, upper: 80, acAttached: true, currentlyCut: true ) )
		XCTAssertTrue( Controller.forceDischargeCut( percent: 81, upper: 80, acAttached: true, currentlyCut: false ) )
	}

	func testEffectWarning() {
		XCTAssertNotNil( Controller.effectWarning( heldFor: 200, chargingEnabled: false, acAttached: true, isCharging: true, amperage: 900 ) )
		XCTAssertNil( Controller.effectWarning( heldFor: 30, chargingEnabled: false, acAttached: true, isCharging: true, amperage: 900 ) )   // firmware still acting
		XCTAssertNil( Controller.effectWarning( heldFor: nil, chargingEnabled: false, acAttached: true, isCharging: true, amperage: 900 ) )
		XCTAssertNil( Controller.effectWarning( heldFor: 200, chargingEnabled: false, acAttached: true, isCharging: false, amperage: 0 ) )
	}

}

final class LimitSettingsTests: XCTestCase {

	func testBandAndSingleLevel() {
		XCTAssertEqual( LimitSettings( limit: 80, lower: 70 ).target, .level( lower: 70, upper: 80 ) )
		XCTAssertEqual( LimitSettings( limit: 80, lower: 80 ).target, .level( lower: 80, upper: 80 ) )
	}

	func testLowerFollowsLimitDown() {
		var s = LimitSettings( limit: 90, lower: 85 )
		s.setLimit( 60 )
		XCTAssertEqual( s.lower, 60 )
		s.setLower( 5 )
		XCTAssertEqual( s.lower, Limits.minMaintain )
		s.setLower( 99 )
		XCTAssertEqual( s.lower, 60 )
	}

	func testSliderClamp() {
		XCTAssertEqual( LimitSettings( limit: 5 ).limit, 20 )
		XCTAssertEqual( LimitSettings( limit: 500 ).limit, 100 )
	}

	func testPresets() {
		var s = LimitSettings()
		s.addPreset( 85 ); s.addPreset( 85 ); s.addPreset( 5 )
		XCTAssertEqual( s.presets, [ 60, 70, 80, 85, 90 ] )
		s.addPreset( 95 ); s.addPreset( 75 )
		XCTAssertEqual( s.presets.count, LimitSettings.maxPresets )
		s.removePreset( 60 )
		XCTAssertFalse( s.presets.contains( 60 ) )
		s.resetPresets()
		XCTAssertEqual( s.presets, LimitSettings.defaultPresets )
		XCTAssertEqual( LimitSettings.presets( from: "60,x,80" ), [ 60, 80 ] )
	}

	func testAdoptDaemonTarget() {
		var s = LimitSettings()
		s.adopt( .level( lower: 50, upper: 60 ), force: true )
		XCTAssertEqual( s.limit, 60 ); XCTAssertEqual( s.lower, 50 ); XCTAssertTrue( s.force )
		s.adopt( .voltage( center: 11.4, hysteresis: 0.1 ), force: false )   // not a band: ignore
		XCTAssertEqual( s.limit, 60 )
		XCTAssertEqual( s.dischargeTarget, 50 )
	}

}
