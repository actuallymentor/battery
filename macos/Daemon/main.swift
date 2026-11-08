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

	/// Touch at launch so a persisted maintain target resumes without waiting for a client, and wire power events
	func boot() {
		log( "daemon \( batteryVersion ) up. \( caps.summary )" )
		_ = maintainer
		_ = scheduler
		events.onWake = { [ weak self ] in log( "wake" ); self?.maintainer?.reconcile(); self?.scheduler?.check() }
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
		guard let control, let reading = Power.read() else { return reply( false, "Battery unreadable" ) }
		var warning = maintainer?.warning( reading )
		if control.backend == .none { warning = control.unsupportedMessage }
		let status = BatteryStatus(
			percent: reading.snapshot.percent, voltage: reading.voltage, remaining: reading.snapshot.remaining, acAttached: reading.snapshot.acAttached,
			chargingEnabled: control.chargingEnabled, discharging: control.adapterCut,
			maintain: maintainer?.target?.persisted, forceDischarge: maintainer?.forceDischarge ?? false,
			activity: jobs?.activity, smcKeys: caps.keys.sorted(), daemonVersion: batteryVersion,
			backend: control.backend.rawValue, isCharging: reading.isCharging, amperage: reading.amperage,
			warning: warning, scheduleDays: scheduler?.days ?? 0, nextTopOff: scheduler?.nextRun, cycleCount: reading.cycleCount, healthPercent: reading.healthPercent )
		reply( true, status.encoded() )
	}

	func probe( reply: @escaping ( Bool, String ) -> Void ) {
		guard smc != nil else { return reply( false, "AppleSMC unavailable" ) }
		let values = SMCCapabilities.probeKeys.map { "\( $0 )=\( smc?.read( $0 ) ?? "-" )" }.joined( separator: " " )
		reply( true, "\( caps.summary )\n\( values )" )
	}

	func status( reply: @escaping ( Bool, String ) -> Void ) {
		guard let control, let reading = Power.read() else { return reply( false, "Battery unreadable" ) }
		var out = Report.status( reading.snapshot, voltage: reading.voltage, charging: control.chargingEnabled, maintain: maintainer?.target )
		if let activity = jobs?.activity { out += "\n\( activity )" }
		if let warning = maintainer?.warning( reading ) { out += "\nWarning: \( warning )" }
		if control.backend == .none { out += "\nWarning: \( control.unsupportedMessage )" }
		reply( true, out )
	}

	func statusCSV( reply: @escaping ( Bool, String ) -> Void ) {
		guard let control, let reading = Power.read() else { return reply( false, "Battery unreadable" ) }
		reply( true, Report.csv( reading.snapshot, charging: control.chargingEnabled, discharging: control.adapterCut, maintain: maintainer?.target ) )
	}

	func maintain( _ setting: String, forceDischarge: Bool, reply: @escaping ( Bool, String ) -> Void ) {
		guard let maintainer else { return reply( false, "AppleSMC unavailable" ) }
		guard let target = try? MaintainTarget( persisted: setting ) else { return reply( false, "Invalid maintain target: \( setting )" ) }
		jobs?.cancel()
		if let why = maintainer.start( target, force: forceDischarge ) { return reply( false, why ) }
		reply( true, "Maintaining battery at \( target.display )" )
	}

	func charge( _ percent: Int, reply: @escaping ( Bool, String ) -> Void ) {
		guard let jobs, let control else { return reply( false, "AppleSMC unavailable" ) }
		guard control.backend != .none else { return reply( false, control.unsupportedMessage ) }
		jobs.start( .charge( percent ) )
		reply( true, "Charging to \( percent )%" )
	}

	func discharge( _ percent: Int, reply: @escaping ( Bool, String ) -> Void ) {
		guard let jobs, let control else { return reply( false, "AppleSMC unavailable" ) }
		guard control.caps.canCutAdapter else { return reply( false, "Discharging isn't available on this Mac (no adapter-cut key)." ) }
		jobs.start( .discharge( percent ) )
		reply( true, "Discharging to \( percent )%" )
	}

	func calibrate( reply: @escaping ( Bool, String ) -> Void ) {
		guard let jobs, let control else { return reply( false, "AppleSMC unavailable" ) }
		guard control.caps.canCutAdapter, control.backend != .none else { return reply( false, "Calibration isn't available on this Mac (needs adapter cut and charge control)." ) }
		jobs.start( .calibrate( Calibration() ) )
		reply( true, "Calibration started: \( Calibration().phase.message )" )
	}

	func legacyFound( reply: @escaping ( Bool, String ) -> Void ) {
		guard let uid = NSXPCConnection.current()?.effectiveUserIdentifier else { return reply( false, "No caller" ) }
		reply( true, Legacy.found( uid: uid ).joined( separator: "," ) )
	}

	func removeLegacy( reply: @escaping ( Bool, String ) -> Void ) {
		guard let uid = NSXPCConnection.current()?.effectiveUserIdentifier else { return reply( false, "No caller" ) }
		let removed = Legacy.remove( uid: uid )
		log( "removed v1 leftovers: \( removed )" )
		reply( true, removed.joined( separator: "," ) )
	}

	/// Drop any job and the maintain target, restore stock charging (also clears a firmware limit).
	func resetAll( reply: @escaping ( Bool, String ) -> Void ) {
		jobs?.cancel()
		maintainer?.stop()
		control?.resetAll()
		reply( true, "Charging restored" )
	}

	func recover( reply: @escaping ( Bool, String ) -> Void ) { resetAll( reply: reply ) }

	func stopMaintain( reply: @escaping ( Bool, String ) -> Void ) {
		maintainer?.stop()
		reply( true, "Battery maintenance stopped" )
	}

	/// Manual override: the user asked for a specific state, so nothing else keeps fighting it (#460 / #440).
	func setCharging( _ on: Bool, reply: @escaping ( Bool, String ) -> Void ) {
		guard let control, let reading = Power.read() else { return reply( false, "AppleSMC unavailable" ) }
		guard control.backend != .none else { return reply( false, control.unsupportedMessage ) }
		jobs?.cancel()
		if maintainer?.target != nil { maintainer?.stop(); log( "manual charging override stopped maintain" ) }
		let ok = control.charging( on, level: reading.snapshot.percent )
		reply( ok, ok ? "ok" : "Writing the charge control failed (see `battery logs`)" )
	}

	func setSchedule( _ days: Int, reply: @escaping ( Bool, String ) -> Void ) {
		guard let scheduler else { return reply( false, "AppleSMC unavailable" ) }
		scheduler.set( days: days )
		reply( true, days > 0 ? "Top off every \( days ) days" : "Schedule off" )
	}

	func setAdapter( _ on: Bool, reply: @escaping ( Bool, String ) -> Void ) {
		guard let control else { return reply( false, "AppleSMC unavailable" ) }
		guard control.caps.canCutAdapter else { return reply( false, "No adapter-cut key on this Mac." ) }
		jobs?.cancel()
		let ok = control.adapter( on: on )
		reply( ok, ok ? "ok" : "Writing the adapter control failed (see `battery logs`)" )
	}

}

let service = Service()
let listener = NSXPCListener( machServiceName: batteryDaemonName )
service.boot()
listener.delegate = service
listener.resume()
RunLoop.main.run()
