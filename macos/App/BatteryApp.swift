import SwiftUI
import ServiceManagement

@main
struct BatteryApp: App {

	@State private var daemon = SMAppService.daemon( plistName: "co.palokaj.battery.daemon.plist" )
	@State private var message = ""

	init() {
		// First launch: ask for the daemon. macOS then needs approval under Login Items
		let d = SMAppService.daemon( plistName: "co.palokaj.battery.daemon.plist" )
		if d.status == .notRegistered || d.status == .notFound { try? d.register() }
	}

	var body: some Scene {
		MenuBarExtra( "Battery", systemImage: "battery.100" ) {
			Text( "Daemon: \( label( daemon.status ) )" )
			if !message.isEmpty { Text( message ) }
			Divider()
			Button( "Register daemon" ) { register() }
			Button( "Open Login Items…" ) { SMAppService.openSystemSettingsLoginItems() }
			Divider()
			Button( "Quit" ) { NSApplication.shared.terminate( nil ) }
		}
	}

	private func register() {
		do { try daemon.register(); message = "" }
		catch { message = error.localizedDescription }
	}

	private func label( _ s: SMAppService.Status ) -> String {
		switch s {
		case .enabled: return "enabled"
		case .requiresApproval: return "needs approval"
		case .notRegistered: return "not registered"
		case .notFound: return "not found"
		@unknown default: return "unknown"
		}
	}

}
