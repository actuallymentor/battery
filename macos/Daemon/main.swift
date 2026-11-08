import Foundation
import BatteryCore

/// Root daemon: owns the SMC. Everything else talks to it over XPC.
func log( _ s: String ) { FileHandle.standardError.write( Data( "batteryd: \( s )\n".utf8 ) ) }

final class Service: NSObject, BatteryDaemonXPC, NSXPCListenerDelegate {

	private let smc = SMC()
	private lazy var caps = SMCCapabilities( keys: Set( SMCCapabilities.probeKeys.filter { smc?.has( $0 ) ?? false } ) )
	private lazy var maintainer = smc.map { Maintainer( smc: $0, caps: caps ) }
	private lazy var jobs = smc.flatMap { s in maintainer.map { Jobs( smc: s, caps: caps, maintainer: $0 ) } }

	/// Touch at launch so a persisted maintain target resumes without waiting for a client
	func boot() { _ = maintainer }

	// Callers must be our own signed app or CLI. Debug builds are ad-hoc signed, so skip there.
	private let requirement = """
		anchor apple generic and certificate leaf[subject.OU] = "CAWM399GFD" \
		and ( identifier "co.palokaj.battery" or identifier "co.palokaj.battery.cli" )
		"""

	func listener( _ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection ) -> Bool {
		log( "connection from pid \( c.processIdentifier )" )
		#if !DEBUG
		c.setCodeSigningRequirement( requirement )
		#endif
		c.exportedInterface = NSXPCInterface( with: BatteryDaemonXPC.self )
		c.exportedObject = self
		c.resume()
		return true
	}

	func probe( reply: @escaping ( Bool, String ) -> Void ) {
		log( "probe" )
		guard smc != nil else { return reply( false, "AppleSMC unavailable" ) }
		let values = SMCCapabilities.probeKeys.map { "\( $0 )=\( smc?.read( $0 ) ?? "-" )" }.joined( separator: " " )
		reply( true, "\( caps.summary )\n\( values )" )
	}

	func status( reply: @escaping ( Bool, String ) -> Void ) {
		guard let smc, let reading = Power.read() else { return reply( false, "Battery unreadable" ) }
		let charging = SMCPlan.chargingEnabled( caps ) { smc.read( $0 ) }
		reply( true, Report.status( reading.snapshot, voltage: reading.voltage, charging: charging, maintain: maintainer?.target ) + ( jobs?.activity.map { "\n\( $0 )" } ?? "" ) )
	}

	func statusCSV( reply: @escaping ( Bool, String ) -> Void ) {
		guard let smc, let reading = Power.read() else { return reply( false, "Battery unreadable" ) }
		let charging = SMCPlan.chargingEnabled( caps ) { smc.read( $0 ) }
		let discharging = SMCPlan.discharging( caps ) { smc.read( $0 ) }
		reply( true, Report.csv( reading.snapshot, charging: charging, discharging: discharging, maintain: maintainer?.target ) )
	}

	func maintain( _ setting: String, forceDischarge: Bool, reply: @escaping ( Bool, String ) -> Void ) {
		guard let maintainer else { return reply( false, "AppleSMC unavailable" ) }
		guard let target = try? MaintainTarget( persisted: setting ) else { return reply( false, "Invalid maintain target: \( setting )" ) }
		jobs?.cancel()
		maintainer.start( target, force: forceDischarge )
		reply( true, "Maintaining battery at \( target.display )" )
	}

	func charge( _ percent: Int, reply: @escaping ( Bool, String ) -> Void ) {
		guard let jobs else { return reply( false, "AppleSMC unavailable" ) }
		jobs.start( .charge( percent ) )
		reply( true, "Charging to \( percent )%" )
	}

	func discharge( _ percent: Int, reply: @escaping ( Bool, String ) -> Void ) {
		guard let jobs else { return reply( false, "AppleSMC unavailable" ) }
		jobs.start( .discharge( percent ) )
		reply( true, "Discharging to \( percent )%" )
	}

	func calibrate( reply: @escaping ( Bool, String ) -> Void ) {
		guard let jobs else { return reply( false, "AppleSMC unavailable" ) }
		jobs.start( .calibrate( Calibration() ) )
		reply( true, "Calibration started: \( Calibration().phase.message )" )
	}

	/// Drop any job and let macOS charge normally; the maintain target stays
	func recover( reply: @escaping ( Bool, String ) -> Void ) {
		jobs?.cancel()
		maintainer?.stop()
		reply( true, "Charging restored" )
	}

	func stopMaintain( reply: @escaping ( Bool, String ) -> Void ) {
		maintainer?.stop()
		reply( true, "Battery maintenance stopped" )
	}

	func setCharging( _ on: Bool, reply: @escaping ( Bool, String ) -> Void ) {
		apply( SMCPlan.charging( on, caps ), reply )
	}

	func setAdapter( _ on: Bool, reply: @escaping ( Bool, String ) -> Void ) {
		apply( SMCPlan.adapter( on: on, caps ), reply )
	}

	private func apply( _ writes: [ SMCWrite ]?, _ reply: ( Bool, String ) -> Void ) {
		guard let smc else { return reply( false, "AppleSMC unavailable" ) }
		guard let writes else { return reply( false, "No known charging key on this machine" ) }
		let failed = writes.filter { !smc.write( $0.key, hex: $0.hex ) }
		reply( failed.isEmpty, failed.isEmpty ? "ok" : "write failed: \( failed.map( \.key ).joined( separator: "," ) )" )
	}

}

let service = Service()
let listener = NSXPCListener( machServiceName: batteryDaemonName )
service.boot()
listener.delegate = service
listener.resume()
RunLoop.main.run()
