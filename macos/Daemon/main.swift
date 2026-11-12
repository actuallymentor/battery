import Foundation
import BatteryCore

/// Root daemon: owns the SMC. Everything else talks to it over XPC: one snapshot call, one `run( Command )` call.
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

		// Jobs aren't persisted: after a crash or reboot the adapter must not stay cut, unless an active force-discharge owns it
		let forcing = maintainer.map { $0.state.active != nil && $0.state.force } ?? false
		if !forcing { control?.adapter( on: true ) }

		events.onWake = { [ weak self ] in log( "wake" ); self?.maintainer?.reconcile(); self?.jobs?.reconcile(); self?.scheduler?.check() }
		events.onWillSleep = { [ weak self ] in self?.maintainer?.willSleep() }
		events.onSourceChange = { [ weak self ] in self?.maintainer?.reconcile() }
		events.start()
	}

	// Callers must be our own signed app or CLI. The team comes from this binary's own Info.plist (project.yml DEVELOPMENT_TEAM,
	// embedded as BatteryTeamID), the identifiers from the mach name: <app>.daemon -> <app> and <app>.cli.
	// Debug builds are ad-hoc signed and have no team, so skip there. scripts/release/sign.sh re-verifies this exact requirement.
	private let requirement: String = {
		let team = Bundle.main.object( forInfoDictionaryKey: "BatteryTeamID" ) as? String ?? ""
		let app = batteryDaemonName.split( separator: "." ).dropLast().joined( separator: "." )
		return """
			anchor apple generic and certificate leaf[subject.OU] = "\( team )" \
			and ( identifier "\( app )" or identifier "\( app ).cli" )
			"""
	}()

	func listener( _ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection ) -> Bool {
		#if !DEBUG
		c.setCodeSigningRequirement( requirement )
		#endif
		c.exportedInterface = NSXPCInterface( with: BatteryDaemonXPC.self )
		c.exportedObject = self
		c.resume()
		return true
	}

	// MARK: XPC

	func snapshot( reply: @escaping ( Bool, String ) -> Void ) {
		onMain { [ self ] in
			guard let control, let maintainer, let reading = Power.read() else { return reply( false, "Battery unreadable" ) }
			let status = BatteryStatus(
				percent: reading.snapshot.percent, voltage: reading.voltage, remaining: reading.snapshot.remaining, acAttached: reading.snapshot.acAttached,
				chargingEnabled: control.chargingEnabled, discharging: control.adapterCut,
				maintain: maintainer.state.active, limit: maintainer.state.target, forceDischarge: maintainer.state.force,
				activity: jobs?.activity, smcKeys: caps.keys.sorted(), daemonVersion: batteryFullVersion,
				backend: control.backend, isCharging: reading.isCharging, amperage: reading.amperage,
				warning: Limits.chargeControl( caps ) ?? maintainer.warning( reading ), scheduleDays: scheduler?.days ?? 0, nextTopOff: scheduler?.nextRun,
				cycleCount: reading.cycleCount, healthPercent: reading.healthPercent, cliInstalled: CLILink.installed )
			reply( true, status.encoded() )
		}
	}

	/// Arguments come from any signed client: decode, gate (`Limits.refusal`), then act. Never trust the caller's parsing.
	func run( _ json: String, reply: @escaping ( Bool, String ) -> Void ) {
		let uid = NSXPCConnection.current()?.effectiveUserIdentifier     // thread-local: read before hopping
		guard let command = Command.decode( json ) else { return reply( false, "Unreadable command (version mismatch? update Battery.app)" ) }
		onMain { [ self ] in
			if let answer = housekeeping( command, uid: uid ) { return reply( answer.0, answer.1 ) }
			guard let control, let maintainer, let jobs, let scheduler else { return reply( false, "AppleSMC unavailable" ) }
			if let why = Limits.refusal( command, caps: caps ) { return reply( false, why ) }

			switch command {

			case .maintain( .set( let target, let force, let enabled ) ):
				if enabled { jobs.abort() }     // a remembered-only change (slider while off) leaves a running job alone
				maintainer.set( target, force: force, enabled: enabled )
				reply( true, enabled ? "Maintaining battery at \( target.display )" : "Limit set to \( target.display ), off" )

			case .maintain( .stop ):
				maintainer.stop()
				reply( true, "Battery maintenance stopped" )

			/// Drop any job and the maintain target, restore stock charging (also clears a firmware limit). `maintain recover` and uninstall.
			case .maintain( .recover ):
				jobs.cancel()
				maintainer.stop()
				control.resetAll()
				reply( true, "Charging restored" )

			case .charge( let percent ):
				jobs.start( .charge( percent ) )
				reply( true, "Charging to \( percent )%" )

			case .discharge( let percent ):
				jobs.start( .discharge( percent ) )
				reply( true, "Discharging to \( percent )%" )

			case .calibrate:
				let c = Calibration()
				jobs.start( .calibrate( c ) )
				reply( true, "Calibration started: \( c.phase.message )" )

			/// Manual override: the user asked for a specific state, so nothing else keeps fighting it (#460 / #440).
			case .charging( let on ):
				guard let reading = Power.read() else { return reply( false, "Battery unreadable" ) }
				jobs.abort()
				if control.adapterCutByUs { control.adapter( on: true ) }     // a replaced job may have cut it
				if maintainer.state.active != nil { maintainer.stop(); log( "manual charging override stopped maintain" ) }
				let ok = control.charging( on, level: reading.snapshot.percent )
				reply( ok, ok ? "ok" : "Writing the charge control failed (see `battery logs`)" )

			case .adapter( let on ):
				jobs.abort()
				let ok = control.adapter( on: on )
				reply( ok, ok ? "ok" : "Writing the adapter control failed (see `battery logs`)" )

			case .schedule( let days ):
				scheduler.set( days: days )
				reply( true, days > 0 ? "Top off every \( days ) days" : "Schedule off" )

			/// Full removal: restore charging, forget the schedule, drop the CLI link, delete persisted state and the log. The app unregisters the daemon right after.
			case .uninstall:
				jobs.cancel()
				maintainer.stop()
				scheduler.set( days: 0 )
				control.resetAll()
				CLILink.uninstall()
				// Last: nothing may write state or log lines after this
				try? FileManager.default.removeItem( atPath: batteryStateDir )
				try? FileManager.default.removeItem( atPath: batteryLogPath )
				reply( true, "Charging restored, helper state removed" )

			case .probe:
				let values = SMCCapabilities.probeKeys.map { "\( $0 )=\( smc?.read( $0 ) ?? "-" )" }.joined( separator: " " )
				reply( true, "\( caps.summary )\n\( values )" )

			case .status, .statusCSV, .logs, .version, .help, .update, .reinstall, .installCLI, .uninstallCLI, .legacyFound, .removeLegacy:
				reply( false, "Not a daemon command" )     // local to the CLI, or handled above
			}
		}
	}

	/// Commands that need no SMC: still answered on a Mac without AppleSMC. Nil = not one of these.
	private func housekeeping( _ command: Command, uid: uid_t? ) -> ( Bool, String )? {
		switch command {
		case .installCLI:
			let ( ok, text ) = CLILink.install()
			log( "install CLI: \( text )" )
			return ( ok, text )
		case .uninstallCLI:
			CLILink.uninstall()
			return ( true, "ok" )
		case .legacyFound:
			guard let uid else { return ( false, "No caller" ) }
			return ( true, Legacy.found( uid: uid ).joined( separator: "," ) )
		case .removeLegacy:
			guard let uid else { return ( false, "No caller" ) }
			let removed = Legacy.remove( uid: uid )
			log( "removed v1 leftovers: \( removed )" )
			return ( true, removed.joined( separator: "," ) )
		default:
			return nil
		}
	}

}

let service = Service()
let listener = NSXPCListener( machServiceName: batteryDaemonName )
service.boot()
listener.delegate = service
listener.resume()
RunLoop.main.run()
