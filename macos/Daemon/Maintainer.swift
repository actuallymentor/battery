import Foundation
import BatteryCore

/// `battery maintain`, the daemon half: timer, power reads, the state file, and running what `MaintainState` decides.
/// All rules live in `MaintainState` (BatteryCore, tested). Persisted, so it resumes after reboot / daemon restart.
/// Main-queue only (see `Service.onMain`).
final class Maintainer {

	private let control: ChargeControl
	private let file = URL( fileURLWithPath: batteryStateDir + "/maintain" )
	private var timer: Timer?

	private( set ) var state: MaintainState

	init( control: ChargeControl ) {
		self.control = control
		state = MaintainState( backend: control.backend )
		load()
	}

	// MARK: Start / stop

	/// Pick up the persisted target after a reboot / daemon restart.
	private func load() {
		guard let raw = try? String( contentsOf: file, encoding: .utf8 ), let saved = MaintainState.parse( raw ) else { return }
		// An update can change the backend (CHTE gone, firmware found): what was fine yesterday may be refused today
		if let why = Limits.check( maintain: saved.target, force: saved.force, caps: control.caps ) { return log( "saved target \( saved.target.display ) dropped: \( why )" ) }
		set( saved.target, force: saved.force, enabled: saved.enabled, persist: false )
	}

	/// New target, or the same one switched on/off. Already gated by `Limits.refusal`.
	func set( _ t: MaintainTarget, force: Bool, enabled: Bool, persist: Bool = true ) {
		log( "maintain \( enabled ? "start" : "set, off" ) \( t.display ) [\( control.backend.rawValue )]\( force ? " force-discharge" : "" )" )
		run( state.set( t, force: force, enabled: enabled, reading: reading() ) )
		if persist { save() }
		arm()
	}

	/// Drop the hold, keep the target so the switch can turn it back on. Hardware goes back to stock unless a job owns it.
	func stop() {
		log( "maintain stop" )
		run( state.stop() )
		save()
		arm()
	}

	/// A job (charge/discharge/calibrate) takes over charging; the target is kept.
	func suspend() { timer?.invalidate(); timer = nil; state.suspend() }

	/// The job was replaced by something that now owns the hardware (new target, manual override): just stop waiting for it.
	func release() { state.release() }

	/// Back to maintaining after a job. Switched off: `restoring` hands charging back to macOS, otherwise leave it as the job set it.
	func resume( restoring: Bool ) {
		run( state.resume( restoring: restoring, reading: reading() ) )
		arm()
	}

	/// The timer runs only while there is something to hold
	private func arm() {
		timer?.invalidate(); timer = nil
		guard state.active != nil, !state.suspended else { return }
		timer = Timer.scheduledTimer( withTimeInterval: Controller.maintainPollInterval, repeats: true ) { [ weak self ] _ in self?.tick() }
		tick()
	}

	private func save() {
		try? FileManager.default.createDirectory( at: file.deletingLastPathComponent(), withIntermediateDirectories: true )
		if let line = state.persisted { try? line.write( to: file, atomically: true, encoding: .utf8 ) } else { try? FileManager.default.removeItem( at: file ) }
	}

	// MARK: Events

	/// Plug/unplug, wake: re-evaluate now instead of waiting for the timer.
	func reconcile() { if state.active != nil, !state.suspended { tick() } }

	/// Going to sleep: never sleep with the adapter cut by us (covers jobs too: one flag in ChargeControl).
	func willSleep() {
		guard control.adapterCutByUs else { return }
		control.adapter( on: true )
		log( "sleep: adapter restored" )
	}

	/// Observed effect problem, for the UI. Nil = fine or unknown.
	func warning( _ p: Power.Reading ) -> String? {
		state.warning( reading( p ), isCharging: p.isCharging, amperage: p.amperage )
	}

	// MARK: Loop

	private func tick() {
		guard let p = Power.read() else { return }
		let r = reading( p )
		let intents = state.tick( r )
		for i in intents where i != .led( .green ) && i != .led( .orange ) && i != .led( .off ) {
			log( "maintain \( state.target?.display ?? "" ): \( r.percent )%\( r.lidClosed ? ", lid closed" : "" ) -> \( describe( i ) )" )
		}
		run( intents )
	}

	private func reading( _ p: Power.Reading? = Power.read() ) -> MaintainState.Reading {
		let upper = state.target?.upper ?? 100
		return MaintainState.Reading(
			percent: p?.snapshot.percent ?? 100, voltage: p?.voltage, chargingEnabled: control.chargingEnabled, acAttached: p?.snapshot.acAttached ?? true,
			adapterCut: control.adapterCutByUs, lidClosed: Power.lidClosed,
			firmwareActive: control.backend == .firmwareLimit ? control.firmwareLimitActive( upper: upper ) : nil )
	}

	private func run( _ intents: [ Intent ] ) { control.run( intents ) }

	private func describe( _ i: Intent ) -> String {
		switch i {
		case .charging( let on, _ ): return on ? "charging on" : "charging off"
		case .adapter( let on ): return on ? "force discharge: adapter on" : "force discharge: adapter off"
		case .firmwareLimit( let u, let l ): return "firmware limit missing or changed, re-applying \( l )-\( u )"
		case .led( let c ): return "led \( c )"
		case .resetAll: return "reset"
		}
	}

}
