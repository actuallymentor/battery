import ApplicationServices
import AppKit

/// How a user gets around Battery.app: menu bar item -> popover -> gear menu -> Settings window. All through the real accessibility tree.
public enum GUI {

	public static let bundleID = "co.palokaj.battery"

	public static var app: AX? { AX.app( bundleID: bundleID ) }
	public static var menuBarItem: AX? { app?.extrasMenuBar?.children.first }

	/// Launches the installed app (real LaunchServices open) and waits until its menu bar item exists
	@discardableResult
	public static func launch() -> Bool {
		if menuBarItem == nil { _ = sh( "/usr/bin/open", [ "-a", "/Applications/Battery.app" ] ) }
		return eventually( 20 ) { menuBarItem } != nil
	}

	public static func quit() {
		NSRunningApplication.runningApplications( withBundleIdentifier: bundleID ).forEach { $0.terminate() }
		_ = eventually( 10 ) { app == nil ? true : nil }
	}

	// MARK: Popover

	public static var popover: AX? { app?.windows.first { $0.find( role: "AXCheckBox", label: "Charge limit" ) != nil || $0.find( role: "AXMenuButton", label: "Actions and settings" ) != nil } }

	@discardableResult
	public static func openPopover() -> AX? {
		if let p = popover { return p }
		menuBarItem?.press()
		return eventually( 5 ) { popover }
	}

	/// A leftover confirmation sheet (Calibrate, Uninstall) blocks the window under it
	public static func dismissSheets() {
		for w in app?.windows ?? [] { w.find { $0.role == "AXSheet" }?.find { $0.role == "AXButton" && $0.title == "Cancel" }?.press() }
	}

	/// For failure messages: what the app is showing right now
	public static var snapshot: String { ( app?.windows ?? [] ).map { $0.dump( depth: 4 ) }.joined( separator: "\n" ) }

	/// Escape out of an open gear menu (a leftover menu swallows the next click)
	public static func dismissMenu() {
		gear?.children.first( where: { $0.role == "AXMenu" } )?.perform( "AXCancel" )
	}

	public static func closePopover() {
		dismissMenu()
		guard popover != nil else { return }
		menuBarItem?.press()
		_ = eventually( 5 ) { popover == nil ? true : nil }
	}

	public static var limitSwitch: AX? { popover?.find( role: "AXCheckBox", label: "Charge limit" ) }
	public static var gear: AX? { popover?.find( role: "AXMenuButton", label: "Actions and settings" ) }

	/// "Charge limit 80%" -> 80
	public static var limitText: Int? {
		popover?.find { $0.role == "AXStaticText" && ( $0.value as? String )?.hasPrefix( "Charge limit " ) == true }
			.flatMap { ( $0.value as? String ).flatMap { Int( $0.dropFirst( "Charge limit ".count ).dropLast() ) } }
	}

	// MARK: Gear menu

	/// Opens the gear menu and returns its items' titles (empty titles are separators)
	public static func gearItems() -> [ String ] {
		openPopover()
		if gear?.children.contains( where: { $0.role == "AXMenu" } ) != true { gear?.press() }
		guard let menu = eventually( 5, { gear?.children.first( where: { $0.role == "AXMenu" } ) } ) else { return [] }
		let titles = menu.children.map { $0.title }
		dismissMenu()
		return titles
	}

	/// Presses a gear menu item by its title (prefix match, since the status line and some labels carry numbers)
	@discardableResult
	public static func pick( _ prefix: String ) -> Bool {
		openPopover()
		if gear?.children.contains( where: { $0.role == "AXMenu" } ) != true { gear?.press() }
		guard let item = eventually( 5, { gear?.find { $0.role == "AXMenuItem" && $0.title.hasPrefix( prefix ) } } ) else { return false }
		return item.press()
	}

	// MARK: Settings window

	public static var settings: AX? { app?.windows.first { $0.identifier == "com_apple_SwiftUI_Settings_window" } }

	@discardableResult
	public static func openSettings( tab: String? = nil ) -> AX? {
		// The first press sometimes lands while the popover is still settling: ask again before giving up
		for _ in 0..<3 where settings == nil { _ = pick( "Settings…" ); _ = eventually( 4 ) { settings } }
		guard let w = settings else { return nil }
		if let tab { w.find( role: "AXButton", label: tab )?.press(); Thread.sleep( forTimeInterval: 0.5 ) }
		return w
	}

	public static func closeSettings() {
		settings?.closeButton?.press()
		_ = eventually( 5 ) { settings == nil ? true : nil }
	}

	/// SwiftUI leaves Form toggles unlabeled in the tree: the label is the static text just before the checkbox
	public static func toggle( _ label: String, in root: AX? = settings ) -> AX? {
		guard let root else { return nil }
		let flat = root.all { _ in true }
		guard let i = flat.firstIndex( where: { $0.role == "AXStaticText" && ( $0.value as? String ) == label }) else { return nil }
		return flat[ ( i + 1 )... ].first { $0.role == "AXCheckBox" }
	}

	/// Value shown to the right of a label in the Battery section ("Charging" -> "Enabled")
	public static func row( _ label: String, in root: AX? = settings ) -> String? {
		guard let root else { return nil }
		let texts = root.all { $0.role == "AXStaticText" }.compactMap { $0.value as? String }
		guard let i = texts.firstIndex( of: label ), i + 1 < texts.count else { return nil }
		return texts[ i + 1 ]
	}

	/// The popover's "Cancel and restore charging" button, present while a job runs
	public static var cancelJob: AX? { popover?.find { $0.role == "AXButton" && $0.label.contains( "Cancel and restore charging" ) } }

	/// Any button anywhere in the app (sheets, dialogs, alerts)
	public static func button( _ title: String ) -> AX? { app?.find { $0.role == "AXButton" && ( $0.title == title || $0.desc == title ) } }

}
