import ApplicationServices
import AppKit
import CoreGraphics

/// Thin wrapper over AXUIElement: the real accessibility tree of the running Battery.app, as a screen reader sees it.
public struct AX {

	public let ref: AXUIElement
	public init( _ ref: AXUIElement ) { self.ref = ref }

	public static func app( bundleID: String = "co.palokaj.battery" ) -> AX? {
		NSRunningApplication.runningApplications( withBundleIdentifier: bundleID ).first.map { AX( AXUIElementCreateApplication( $0.processIdentifier ) ) }
	}

	public static var trusted: Bool { AXIsProcessTrusted() }

	private func attr( _ name: String ) -> AnyObject? {
		var v: CFTypeRef?
		return AXUIElementCopyAttributeValue( ref, name as CFString, &v ) == .success ? v : nil
	}

	public var role: String { attr( kAXRoleAttribute ) as? String ?? "" }
	public var title: String { attr( kAXTitleAttribute ) as? String ?? "" }
	public var desc: String { attr( kAXDescriptionAttribute ) as? String ?? "" }
	public var help: String { attr( kAXHelpAttribute ) as? String ?? "" }
	public var identifier: String { attr( "AXIdentifier" ) as? String ?? "" }
	public var value: Any? { attr( kAXValueAttribute ) }
	public var enabled: Bool { ( attr( kAXEnabledAttribute ) as? Bool ) ?? true }
	public var children: [ AX ] { ( attr( kAXChildrenAttribute ) as? [ AXUIElement ] ?? [] ).map( AX.init ) }
	public var windows: [ AX ] { ( attr( kAXWindowsAttribute ) as? [ AXUIElement ] ?? [] ).map( AX.init ) }
	public var focused: AX? { ( attr( kAXFocusedUIElementAttribute ) ).map { AX( $0 as! AXUIElement ) } }
	public var closeButton: AX? { ( attr( kAXCloseButtonAttribute ) ).map { AX( $0 as! AXUIElement ) } }
	public var extrasMenuBar: AX? { ( attr( "AXExtrasMenuBar" ) ).map { AX( $0 as! AXUIElement ) } }

	/// On-screen frame (top-left origin, like CGEvent coordinates)
	public var frame: CGRect? {
		guard let p = attr( kAXPositionAttribute ), let s = attr( kAXSizeAttribute ) else { return nil }
		var origin = CGPoint.zero, size = CGSize.zero
		AXValueGetValue( p as! AXValue, .cgPoint, &origin ); AXValueGetValue( s as! AXValue, .cgSize, &size )
		return CGRect( origin: origin, size: size )
	}

	/// The label a user would hear: title, else description, else string value
	public var label: String { [ title, desc, value as? String ?? "" ].first { !$0.isEmpty } ?? "" }
	public var on: Bool { ( value as? NSNumber )?.intValue == 1 }
	public var number: Double? { ( value as? NSNumber )?.doubleValue }

	@discardableResult public func press() -> Bool { AXUIElementPerformAction( ref, kAXPressAction as CFString ) == .success }
	@discardableResult public func perform( _ action: String ) -> Bool { AXUIElementPerformAction( ref, action as CFString ) == .success }
	@discardableResult public func set( _ v: CFTypeRef ) -> Bool { AXUIElementSetAttributeValue( ref, kAXValueAttribute as CFString, v ) == .success }

	/// Steps a slider with the keyboard-equivalent increment/decrement actions (SwiftUI sliders refuse a direct value set)
	@discardableResult
	public func slide( to target: Int ) -> Bool {
		for _ in 0..<200 {
			guard let now = number.map( Int.init ) else { return false }
			if now == target { return true }
			guard perform( now < target ? "AXIncrement" : "AXDecrement" ) else { return false }
			Thread.sleep( forTimeInterval: 0.05 )
		}
		return false
	}

	/// Depth-first search of the subtree
	public func find( depth: Int = 12, _ match: ( AX ) -> Bool ) -> AX? {
		if match( self ) { return self }
		guard depth > 0 else { return nil }
		for c in children { if let hit = c.find( depth: depth - 1, match ) { return hit } }
		return nil
	}

	public func all( depth: Int = 12, _ match: ( AX ) -> Bool ) -> [ AX ] {
		( match( self ) ? [ self ] : [] ) + ( depth > 0 ? children.flatMap { $0.all( depth: depth - 1, match ) } : [] )
	}

	public func find( role: String, label: String, contains: Bool = false ) -> AX? {
		find { $0.role == role && [ $0.title, $0.desc, $0.value as? String ?? "" ].contains { contains ? $0.contains( label ) : $0 == label } }
	}

	public func dump( indent: Int = 0, depth: Int = 10 ) -> String {
		let line = String( repeating: "  ", count: indent ) + "\( role ) title=\( title.debugDescription ) desc=\( desc.debugDescription ) id=\( identifier.debugDescription ) value=\( value.map { "\( $0 )" } ?? "nil" ) help=\( help.debugDescription )"
		guard depth > 0 else { return line }
		return ( [ line ] + children.map { $0.dump( indent: indent + 1, depth: depth - 1 ) } ).joined( separator: "\n" )
	}

}

public enum Screen {
	/// A locked screen hides every other app's UI from Accessibility (windows come back as the app itself)
	public static var locked: Bool { ( CGSessionCopyCurrentDictionary() as? [ String: Any ] )?[ "CGSSessionScreenIsLocked" ] as? Bool ?? false }
}
