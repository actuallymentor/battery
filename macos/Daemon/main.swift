import Foundation
import BatteryCore

/// Root daemon: owns the SMC. Everything else talks to it over XPC.
func log( _ s: String ) { FileHandle.standardError.write( Data( "batteryd: \( s )\n".utf8 ) ) }

final class Service: NSObject, BatteryDaemonXPC, NSXPCListenerDelegate {

	private let smc = SMC()
	private lazy var caps = SMCCapabilities( keys: Set( SMCCapabilities.probeKeys.filter { smc?.has( $0 ) ?? false } ) )

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
		guard let smc else { return reply( false, "AppleSMC unavailable" ) }
		let charging = SMCPlan.chargingEnabled( caps ) { smc.read( $0 ) }
		let discharging = SMCPlan.discharging( caps ) { smc.read( $0 ) }
		reply( true, "charging=\( charging.map { "\( $0 )" } ?? "unknown" ) discharging=\( discharging.map { "\( $0 )" } ?? "unknown" )" )
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
listener.delegate = service
listener.resume()
RunLoop.main.run()
