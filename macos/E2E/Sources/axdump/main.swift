import ApplicationServices
import E2EKit
import Foundation

// Debug aid: `axdump [menu] [gear] [tab:General]` prints Battery.app's accessibility tree after performing the listed steps
if CommandLine.arguments.contains( "lockstate" ) { print( "locked:", Screen.locked ? "yes" : "no" ); exit( 0 ) }
guard AX.trusted else { print( "Not Accessibility-trusted: run from Terminal (see scripts/e2e.sh)" ); exit( 2 ) }
// `app=com.apple.systempreferences` points every later step at another app (default: Battery)
let bundle = CommandLine.arguments.first { $0.hasPrefix( "app=" ) }.map { String( $0.dropFirst( 4 ) ) } ?? "co.palokaj.battery"
guard let app = AX.app( bundleID: bundle ) else { print( bundle, "is not running" ); exit( 1 ) }
func settle() { Thread.sleep( forTimeInterval: 1.0 ) }
for step in CommandLine.arguments.dropFirst() {
	switch step {
	case let s where s.hasPrefix( "app=" ): break
	case let s where s.hasPrefix( "id:" ): print( "press \(s):", app.find { $0.identifier == String( s.dropFirst( 3 ) ) }?.press() as Any )
	case "focus": print( "focused:", app.focused.map { "\($0.role) \($0.title) \($0.desc)" } ?? "none" )
	case "menu": GUI.openPopover()
	case "gear":
		let g = app.find( role: "AXMenuButton", label: "Actions and settings" )
		print( "gear press:", g?.press() as Any, "children:", g?.children.count as Any )
		settle()
		print( "gear after:", g?.children.map { $0.role } as Any )
		print( "focused:", app.focused?.dump( depth: 3 ) ?? "none" )
	case let s where s.hasPrefix( "tab:" ): app.find( role: "AXButton", label: String( s.dropFirst( 4 ) ) )?.press()
	case let s where s.hasPrefix( "item:" ): app.find { $0.role == "AXMenuItem" && $0.title.hasPrefix( String( s.dropFirst( 5 ) ) ) }?.press()
	case let s where s.hasPrefix( "press:" ): print( "press \(s.dropFirst( 6 )):", app.find { $0.role == "AXButton" && $0.label.contains( String( s.dropFirst( 6 ) ) ) }?.press() as Any )
	case let s where s.hasPrefix( "slide:" ): print( "slide:", GUI.openSettings( tab: "Charging" )?.find( role: "AXSlider", label: "Charge limit" )?.slide( to: Int( s.dropFirst( 6 ) )! ) as Any )
	default: print( "unknown step", step )
	}
	settle()
}
for w in app.windows { print( w.dump( depth: 9 ) ) }
if let m = app.extrasMenuBar { _ = m }
