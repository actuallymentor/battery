import Foundation
import BatteryCore

/// `battery maintain`: holds the battery inside a band. Persisted, so it resumes after reboot / daemon restart.
/// Firmware backend: hands the band to the firmware and only re-asserts it. Other backends: re-evaluated on a
/// timer, on plug/unplug and on wake, flipping charging via the SMC.
final class Maintainer {

	private let control: ChargeControl
	private let file = URL( fileURLWithPath: "/var/db/co.palokaj.battery/maintain" )
	private var timer: Timer?
	private var refilling = false
	private var adapterCut = false

	/// When we last asked the hardware to hold. Used to judge "requested vs effective" after a grace period.
	private var heldSince: Date?

	private( set ) var target: MaintainTarget?
	private( set ) var forceDischarge = false

	init( control: ChargeControl ) {
		self.control = control
		load()
	}

	// MARK: Start / stop

	/// Pick up the persisted target after a reboot / daemon restart.
	private func load() {
		guard let raw = try? String( contentsOf: file, encoding: .utf8 ) else { return }
		let force = raw.contains( "--force-discharge" )
		let setting = raw.replacingOccurrences( of: " --force-discharge", with: "" ).trimmingCharacters( in: .whitespacesAndNewlines )
		if let t = try? MaintainTarget( persisted: setting ) { _ = start( t, force: force, persist: false ) }
	}

	/// Nil on success, otherwise why this Mac can't do it.
	func start( _ t: MaintainTarget, force: Bool, persist: Bool = true ) -> String? {

		if control.backend == .none { return control.unsupportedMessage }
		if control.backend == .firmwareLimit, case .voltage = t { return "Voltage targets aren't available on this Mac (firmware limit). Use a percentage." }
		if control.backend == .firmwareLimit, case .level( _, let upper ) = t, upper < SMCPlan.firmwareFloor { return "This Mac's firmware can't hold below \( SMCPlan.firmwareFloor )%." }
		if force, !control.caps.canCutAdapter { return "Force discharge isn't available on this Mac (no adapter-cut key)." }

		log( "maintain start \( t.display ) [\( control.backend.rawValue )]\( force ? " force-discharge" : "" )" )
		target = t
		forceDischarge = force
		refilling = false
		heldSince = nil

		if persist {
			try? FileManager.default.createDirectory( at: file.deletingLastPathComponent(), withIntermediateDirectories: true )
			try? ( t.persisted + ( force ? " --force-discharge" : "" ) ).write( to: file, atomically: true, encoding: .utf8 )
		}

		timer?.invalidate()
		timer = Timer.scheduledTimer( withTimeInterval: Controller.maintainPollInterval, repeats: true ) { [ weak self ] _ in self?.tick() }
		tick()
		return nil
	}

	/// Stop and hand charging back to macOS.
	func stop() {
		log( "maintain stop" )
		timer?.invalidate(); timer = nil
		target = nil
		heldSince = nil
		try? FileManager.default.removeItem( at: file )
		restore()
	}

	/// A job (charge/discharge/calibrate) takes over charging; the target is kept.
	func suspend() { timer?.invalidate(); timer = nil }

	/// Back to maintaining after a job. Without a target: `restoring` hands charging back to macOS, otherwise leave it as the job set it.
	func resume( restoring: Bool ) {
		if let target { _ = start( target, force: forceDischarge, persist: false ) } else if restoring { restore() }
	}

	private func restore() {
		control.resetAll()
		adapterCut = false
		refilling = false
	}

	// MARK: Events

	/// Plug/unplug, wake: re-evaluate now instead of waiting for the timer.
	func reconcile() { if target != nil { tick() } }

	/// Going to sleep: never sleep with the adapter cut by us.
	func willSleep() {
		guard control.adapterCutByUs else { return }
		control.adapter( on: true )
		adapterCut = false
		log( "sleep: adapter restored" )
	}

	/// Observed effect problem, for the UI. Nil = fine or unknown.
	func warning( _ p: Power.Reading ) -> String? {
		guard target != nil else { return nil }
		guard let since = heldSince, Date().timeIntervalSince( since ) > 120 else { return nil }
		if control.chargingEnabled == false, p.snapshot.acAttached, p.isCharging == true, ( p.amperage ?? 0 ) > 100 {
			return "macOS is still charging even though the limit is set. This Mac may be ignoring the charge control."
		}
		return nil
	}

	// MARK: Loop

	private func tick() {
		guard let target, let reading = Power.read() else { return }
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

		// --force-discharge: above the band on AC, cut the adapter until we are back inside it
		if forceDischarge, case .level( _, let upper ) = target {
			let over = percent > upper && state.acAttached
			if over != adapterCut {
				control.adapter( on: !over )
				adapterCut = over
			}
		}

		let d = Controller.decide( target, state )
		if let r = d.refilling { refilling = r }

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
