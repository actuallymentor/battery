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
	// An unregistered Mach name never errors, it just hangs: give up after a while
	DispatchQueue.main.asyncAfter( deadline: .now() + 15 ) {
		FileHandle.standardError.write( Data( "battery: daemon not responding. Open Battery.app and approve it in Login Items.\n".utf8 ) )
		exit( 1 )
	}
	call( proxy ) { ok, text in
		print( text )
		exit( ok ? 0 : 1 )
	}
	dispatchMain()
}

/// `status` and `status_csv`: the daemon sends one snapshot, formatting happens here (less code running as root)
func remoteStatus( _ render: @escaping ( BatteryStatus ) -> String ) -> Never {
	remote { proxy, reply in
		proxy.snapshot { ok, text in
			guard ok else { return reply( false, text ) }
			guard let status = BatteryStatus.decode( text ) else { return reply( false, "Unreadable status from the helper (version mismatch? update Battery.app)" ) }
			reply( true, render( status ) )
		}
	}
}

do {
	let command = try Command( arguments: args )
	switch command {
	case .help: print( Report.help )
	case .version: print( batteryVersion )
	case .status: remoteStatus { Report.status( $0 ) }
	case .statusCSV: remoteStatus { Report.csv( $0 ) }
	case .update, .reinstall:
		print( "Updates and reinstalls are handled by Battery.app: menu bar icon -> Settings, or download the latest release." )
	case .logs( let lines ):
		let text = ( try? String( contentsOfFile: batteryLogPath, encoding: .utf8 ) ) ?? ""
		print( text.split( separator: "\n" ).suffix( lines ).joined( separator: "\n" ) )
	case .uninstall:
		remote { proxy, reply in
			proxy.run( command.encoded() ) { ok, text in
				reply( ok, ok ? "\( text ). Now turn Battery off in Login Items and delete Battery.app (or use Settings -> Uninstall in the app)." : text )
			}
		}
	default: remote { $0.run( command.encoded(), reply: $1 ) }
	}
} catch {
	FileHandle.standardError.write( Data( "battery: \( error )\n".utf8 ) )
	exit( 1 )
}
