import SwiftUI
import ServiceManagement

@main
struct BatteryApp: App {

	@State private var daemon = SMAppService.daemon( plistName: "co.palokaj.battery.daemon.plist" )
	@State private var message = ""

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
