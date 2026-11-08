import Foundation
import BatteryCore

/// `battery` CLI: parse locally, run on the daemon.
let args = Array( CommandLine.arguments.dropFirst() )

func remote( _ call: ( BatteryDaemonXPC, @escaping ( Bool, String ) -> Void ) -> Void ) -> Never {
	let conn = NSXPCConnection( machServiceName: batteryDaemonName, options: .privileged )
	conn.remoteObjectInterface = NSXPCInterface( with: BatteryDaemonXPC.self )
	conn.resume()
	let proxy = conn.remoteObjectProxyWithErrorHandler { e in
		FileHandle.standardError.write( Data( "battery: daemon unreachable (\( e.localizedDescription )). Open Battery.app and approve it in Login Items.\n".utf8 ) )
		exit( 1 )
	} as! BatteryDaemonXPC
	call( proxy ) { ok, text in
		print( text )
		exit( ok ? 0 : 1 )
	}
	dispatchMain()
}

// Dev-only probe, not part of the v1 command set
if args.first == "probe" { remote { $0.probe( reply: $1 ) } }

do {
	switch try Command( arguments: args ) {
	case .help: print( Report.help )
	case .status: remote { $0.status( reply: $1 ) }
	case .charging( let on ): remote { $0.setCharging( on, reply: $1 ) }
	case .adapter( let on ): remote { $0.setAdapter( on, reply: $1 ) }
	default:
		FileHandle.standardError.write( Data( "battery: not implemented yet\n".utf8 ) )
		exit( 2 )
	}
} catch {
	FileHandle.standardError.write( Data( "battery: \( error )\n".utf8 ) )
	exit( 1 )
}
