import Foundation
import BatteryCore

/// Root daemon: owns the SMC. Everything else talks to it over XPC.
final class Service: NSObject, BatteryDaemonXPC, NSXPCListenerDelegate {

	private let smc = SMC()
	private lazy var caps = SMCCapabilities( keys: Set( SMCCapabilities.probeKeys.filter { smc?.has( $0 ) ?? false } ) )
	private lazy var control = smc.map { ChargeControl( smc: $0, caps: caps ) }
	private lazy var maintainer = control.map { Maintainer( control: $0 ) }
	private lazy var jobs = control.flatMap { c in maintainer.map { Jobs( control: c, maintainer: $0 ) } }
	private lazy var scheduler = jobs.map { Scheduler( jobs: $0 ) }
	private let events = PowerEvents()

	/// ALL daemon state lives on the main queue: timers need its run loop (a Timer created on an XPC thread never fires),
	/// and power events, timers and XPC calls then never race. Every XPC method hops here first.
	private func onMain( _ work: @escaping () -> Void ) { DispatchQueue.main.async( execute: work ) }

	/// Touch at launch so a persisted maintain target resumes without waiting for a client, and wire power events
	func boot() {
		log( "daemon \( batteryVersion ) up. \( caps.summary )" )
		_ = maintainer
		_ = scheduler

		// Jobs and force-discharge aren't persisted: after a crash or reboot the adapter must not stay cut
		if maintainer?.forceDischarge != true { control?.adapter( on: true ) }

		events.onWake = { [ weak self ] in log( "wake" ); self?.maintainer?.reconcile(); self?.jobs?.reconcile(); self?.scheduler?.check() }
		events.onWillSleep = { [ weak self ] in self?.maintainer?.willSleep() }
		events.onSourceChange = { [ weak self ] in self?.maintainer?.reconcile() }
		events.start()
	}

	// Callers must be our own signed app or CLI. Debug builds are ad-hoc signed, so skip there.
	private let requirement = """
		anchor apple generic and certificate leaf[subject.OU] = "CAWM399GFD" \
		and ( identifier "co.palokaj.battery" or identifier "co.palokaj.battery.cli" )
		"""

	func listener( _ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection ) -> Bool {
		#if !DEBUG
		c.setCodeSigningRequirement( requirement )
		#endif
		c.exportedInterface = NSXPCInterface( with: BatteryDaemonXPC.self )
		c.exportedObject = self
		c.resume()
		return true
	}

	func snapshot( reply: @escaping ( Bool, String ) -> Void ) {
		onMain { [ self ] in
			guard let control, let reading = Power.read() else { return reply( false, "Battery unreadable" ) }
			var warning = maintainer?.warning( reading )
			if control.backend == .none { warning = control.unsupportedMessage }
			let status = BatteryStatus(
				percent: reading.snapshot.percent, voltage: reading.voltage, remaining: reading.snapshot.remaining, acAttached: reading.snapshot.acAttached,
				chargingEnabled: control.chargingEnabled, discharging: control.adapterCut,
				maintain: maintainer?.target?.persisted, forceDischarge: maintainer?.forceDischarge ?? false,
				activity: jobs?.activity, smcKeys: caps.keys.sorted(), daemonVersion: batteryVersion,
				backend: control.backend.rawValue, isCharging: reading.isCharging, amperage: reading.amperage,
				warning: warning, scheduleDays: scheduler?.days ?? 0, nextTopOff: scheduler?.nextRun,
				cycleCount: reading.cycleCount, healthPercent: reading.healthPercent )
			reply( true, status.encoded() )
		}
	}

	func probe( reply: @escaping ( Bool, String ) -> Void ) {
		onMain { [ self ] in
			guard smc != nil else { return reply( false, "AppleSMC unavailable" ) }
			let values = SMCCapabilities.probeKeys.map { "\( $0 )=\( smc?.read( $0 ) ?? "-" )" }.joined( separator: " " )
			reply( true, "\( caps.summary )\n\( values )" )
		}
	}

	// MARK: Maintain and jobs. Arguments come from any signed client: validate here, never trust the caller.

	func maintain( _ setting: String, forceDischarge: Bool, reply: @escaping ( Bool, String ) -> Void ) {
		onMain { [ self ] in
			guard let maintainer else { return reply( false, "AppleSMC unavailable" ) }
			guard let target = try? MaintainTarget( persisted: setting ) else { return reply( false, "Invalid maintain target: \( setting )" ) }
			jobs?.abort()
			if let why = maintainer.start( target, force: forceDischarge ) { return reply( false, why ) }
			reply( true, "Maintaining battery at \( target.display )" )
		}
	}

	func stopMaintain( reply: @escaping ( Bool, String ) -> Void ) {
		onMain { [ self ] in
			maintainer?.stop()
			reply( true, "Battery maintenance stopped" )
		}
	}

	func charge( _ percent: Int, reply: @escaping ( Bool, String ) -> Void ) {
		onMain { [ self ] in
			guard let jobs, let control else { return reply( false, "AppleSMC unavailable" ) }
			if let why = Limits.check( charge: percent ) { return reply( false, why ) }
			guard control.backend != .none else { return reply( false, control.unsupportedMessage ) }
			jobs.start( .charge( percent ) )
			reply( true, "Charging to \( percent )%" )
		}
	}

	func discharge( _ percent: Int, reply: @escaping ( Bool, String ) -> Void ) {
		onMain { [ self ] in
			guard let jobs, let control else { return reply( false, "AppleSMC unavailable" ) }
			if let why = Limits.check( discharge: percent ) { return reply( false, why ) }
			guard control.caps.canCutAdapter else { return reply( false, "Discharging isn't available on this Mac (no adapter-cut key)." ) }
			jobs.start( .discharge( percent ) )
			reply( true, "Discharging to \( percent )%" )
		}
	}

	func calibrate( reply: @escaping ( Bool, String ) -> Void ) {
		onMain { [ self ] in
			guard let jobs, let control else { return reply( false, "AppleSMC unavailable" ) }
			guard control.caps.canCutAdapter, control.backend != .none else { return reply( false, "Calibration isn't available on this Mac (needs adapter cut and charge control)." ) }
			let c = Calibration()
			jobs.start( .calibrate( c ) )
			reply( true, "Calibration started: \( c.phase.message )" )
		}
	}

	/// Drop any job and the maintain target, restore stock charging (also clears a firmware limit). `maintain recover` and uninstall.
	func resetAll( reply: @escaping ( Bool, String ) -> Void ) {
		onMain { [ self ] in
			jobs?.cancel()
			maintainer?.stop()
			control?.resetAll()
			reply( true, "Charging restored" )
		}
	}

	/// Manual override: the user asked for a specific state, so nothing else keeps fighting it (#460 / #440).
	func setCharging( _ on: Bool, reply: @escaping ( Bool, String ) -> Void ) {
		onMain { [ self ] in
			guard let control, let reading = Power.read() else { return reply( false, "AppleSMC unavailable" ) }
			guard control.backend != .none else { return reply( false, control.unsupportedMessage ) }
			jobs?.abort()
			if control.adapterCutByUs { control.adapter( on: true ) }     // a replaced job may have cut it
			if maintainer?.target != nil { maintainer?.stop(); log( "manual charging override stopped maintain" ) }
			let ok = control.charging( on, level: reading.snapshot.percent )
			reply( ok, ok ? "ok" : "Writing the charge control failed (see `battery logs`)" )
		}
	}

	func setAdapter( _ on: Bool, reply: @escaping ( Bool, String ) -> Void ) {
		onMain { [ self ] in
			guard let control else { return reply( false, "AppleSMC unavailable" ) }
			guard control.caps.canCutAdapter else { return reply( false, "No adapter-cut key on this Mac." ) }
			jobs?.abort()
			let ok = control.adapter( on: on )
			reply( ok, ok ? "ok" : "Writing the adapter control failed (see `battery logs`)" )
		}
	}

	func setSchedule( _ days: Int, reply: @escaping ( Bool, String ) -> Void ) {
		onMain { [ self ] in
			guard let scheduler else { return reply( false, "AppleSMC unavailable" ) }
			guard Limits.scheduleDays.contains( days ) else { return reply( false, "Schedule must be 0-90 days." ) }
			scheduler.set( days: days )
			reply( true, days > 0 ? "Top off every \( days ) days" : "Schedule off" )
		}
	}

	// MARK: Housekeeping

	func legacyFound( reply: @escaping ( Bool, String ) -> Void ) {
		guard let uid = NSXPCConnection.current()?.effectiveUserIdentifier else { return reply( false, "No caller" ) }   // thread-local: read before hopping
		onMain { reply( true, Legacy.found( uid: uid ).joined( separator: "," ) ) }
	}

	func removeLegacy( reply: @escaping ( Bool, String ) -> Void ) {
		guard let uid = NSXPCConnection.current()?.effectiveUserIdentifier else { return reply( false, "No caller" ) }
		onMain {
			let removed = Legacy.remove( uid: uid )
			log( "removed v1 leftovers: \( removed )" )
			reply( true, removed.joined( separator: "," ) )
		}
	}

	func installCLI( reply: @escaping ( Bool, String ) -> Void ) {
		onMain {
			let ( ok, text ) = CLILink.install()
			log( "install CLI: \( text )" )
			reply( ok, text )
		}
	}

	func uninstallCLI( reply: @escaping ( Bool, String ) -> Void ) {
		onMain {
			CLILink.uninstall()
			reply( true, "ok" )
		}
	}

}

let service = Service()
let listener = NSXPCListener( machServiceName: batteryDaemonName )
service.boot()
listener.delegate = service
listener.resume()
RunLoop.main.run()
