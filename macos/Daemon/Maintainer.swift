import Foundation
import BatteryCore

/// `battery maintain`: holds the battery inside a band. Persisted, so it resumes after reboot / daemon restart.
/// Firmware backend: hands the band to the firmware and only re-asserts it. Other backends: re-evaluated on a
/// timer, on plug/unplug and on wake, flipping charging via the SMC.
/// Main-queue only (see `Service.onMain`).
final class Maintainer {

	private let control: ChargeControl
	private let file = URL( fileURLWithPath: batteryStateDir + "/maintain" )
	private var timer: Timer?
	private var refilling = false

	/// When we last asked the hardware to hold. Used to judge "requested vs effective" after a grace period.
	private var heldSince: Date?

	private( set ) var target: MaintainTarget?
	private( set ) var forceDischarge = false

	/// A job owns the hardware: keep the target, do nothing until the job hands back (`resume`) or is replaced (`release`).
	private var suspended = false

	init( control: ChargeControl ) {
		self.control = control
		load()
	}

	// MARK: Start / stop

	/// Pick up the persisted target after a reboot / daemon restart.
	private func load() {
		guard let raw = try? String( contentsOf: file, encoding: .utf8 ), let saved = MaintainTarget.parseLine( raw ) else { return }
		_ = start( saved.target, force: saved.force, persist: false )
	}

	/// Nil on success, otherwise why this Mac can't do it.
	func start( _ t: MaintainTarget, force: Bool, persist: Bool = true ) -> String? {
		if let why = Limits.check( maintain: t, force: force, caps: control.caps ) { return why }

		log( "maintain start \( t.display ) [\( control.backend.rawValue )]\( force ? " force-discharge" : "" )" )
		let percent = Power.read()?.snapshot.percent ?? 100
		refilling = control.backend != .firmwareLimit && Controller.refillsAfterRetarget( from: target, to: t, percent: percent )
		target = t
		forceDischarge = force
		suspended = false
		heldSince = nil

		// Limit raised above the battery: charge up to it (the firmware backend does this on its own)
		if refilling {
			log( "maintain \( t.display ): limit raised, \( percent )% -> charging on" )
			control.charging( true )
		}

		// A replaced job may have left the adapter cut; only force-discharge is allowed to keep it that way
		if !force, control.adapterCutByUs { control.adapter( on: true ) }

		if persist {
			try? FileManager.default.createDirectory( at: file.deletingLastPathComponent(), withIntermediateDirectories: true )
			try? t.persistedLine( force: force ).write( to: file, atomically: true, encoding: .utf8 )
		}

		timer?.invalidate()
		timer = Timer.scheduledTimer( withTimeInterval: Controller.maintainPollInterval, repeats: true ) { [ weak self ] _ in self?.tick() }
		tick()
		return nil
	}

	/// Drop the target. Hardware goes back to stock unless a job is running: that one owns it.
	func stop() {
		log( "maintain stop" )
		timer?.invalidate(); timer = nil
		target = nil
		heldSince = nil
		try? FileManager.default.removeItem( at: file )
		if !suspended { restore() }
	}

	/// A job (charge/discharge/calibrate) takes over charging; the target is kept.
	func suspend() { timer?.invalidate(); timer = nil; suspended = true }

	/// The job was replaced by something that now owns the hardware (new target, manual override): just stop waiting for it.
	func release() { suspended = false }

	/// Back to maintaining after a job. Without a target: `restoring` hands charging back to macOS, otherwise leave it as the job set it.
	func resume( restoring: Bool ) {
		suspended = false
		if let target { _ = start( target, force: forceDischarge, persist: false ) } else if restoring { restore() }
	}

	private func restore() {
		control.resetAll()
		refilling = false
		heldSince = nil
	}

	// MARK: Events

	/// Plug/unplug, wake: re-evaluate now instead of waiting for the timer.
	func reconcile() { if target != nil, !suspended { tick() } }

	/// Going to sleep: never sleep with the adapter cut by us (covers jobs too: one flag in ChargeControl).
	func willSleep() {
		guard control.adapterCutByUs else { return }
		control.adapter( on: true )
		log( "sleep: adapter restored" )
	}

	/// Observed effect problem, for the UI. Nil = fine or unknown.
	func warning( _ p: Power.Reading ) -> String? {
		guard target != nil else { return nil }
		return Controller.effectWarning( heldFor: heldSince.map { Date().timeIntervalSince( $0 ) }, chargingEnabled: control.chargingEnabled,
		                                 acAttached: p.snapshot.acAttached, isCharging: p.isCharging, amperage: p.amperage )
	}

	// MARK: Loop

	private func tick() {
		guard let target, !suspended, let reading = Power.read() else { return }
		let percent = reading.snapshot.percent

		// Firmware: the limit lives in the SMC. Just make sure it is still there.
		if control.backend == .firmwareLimit, case .level( let lower, let upper ) = target {
			if upper < 100, !control.firmwareLimitActive( upper: upper ) {
				log( "firmware limit missing or changed, re-applying \( lower )-\( upper )" )
				control.firmwareLimit( upper: upper, lower: lower )
			}
			if heldSince == nil, percent >= upper { heldSince = Date() }
			return
		}

		let state = BatteryState( percent: percent, voltage: reading.voltage, chargingEnabled: control.chargingEnabled,
		                          acAttached: reading.snapshot.acAttached, refilling: refilling )

		if forceDischarge, case .level( _, let upper ) = target {
			let cut = control.adapterCutByUs
			let lid = Power.lidClosed
			let want = Controller.forceDischargeCut( percent: percent, upper: upper, acAttached: state.acAttached, currentlyCut: cut, lidClosed: lid )
			if want != cut {
				log( want ? "force discharge: \( percent )% > \( upper )%, adapter off" : "force discharge: adapter on (\( lid ? "lid closed" : "\( percent )% at or under \( upper )%" ))" )
				control.adapter( on: !want )
			}
		}

		let d = Controller.decide( target, state )
		if let r = d.refilling { refilling = r }
		if let led = d.led { control.led( led ) }

		switch d.action {
		case .enableCharging:
			log( "maintain \( target.display ): \( percent )% -> charging on" )
			control.charging( true )
			heldSince = nil
		case .disableCharging:
			log( "maintain \( target.display ): \( percent )% -> charging off" )
			control.charging( false, level: percent )
			heldSince = Date()
		case .none:
			if state.chargingEnabled == false, heldSince == nil { heldSince = Date() }
		}
	}

}
