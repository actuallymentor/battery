import CoreGraphics
import Foundation

/// A real pointer: CGEvents posted to the HID stream, the same path a trackpad takes. Needs the runner's Accessibility grant.
public enum Mouse {

	public static func down( _ p: CGPoint ) { post( .leftMouseDown, p ) }
	public static func up( _ p: CGPoint ) { post( .leftMouseUp, p ) }

	/// Drag in small steps, like a hand would (one big jump can skip the control's tracking)
	public static func drag( from a: CGPoint, to b: CGPoint, steps: Int = 20 ) {
		for i in 1...steps {
			let t = CGFloat( i ) / CGFloat( steps )
			post( .leftMouseDragged, CGPoint( x: a.x + ( b.x - a.x ) * t, y: a.y + ( b.y - a.y ) * t ) )
			Thread.sleep( forTimeInterval: 0.02 )
		}
	}

	private static func post( _ type: CGEventType, _ p: CGPoint ) {
		CGEvent( mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left )?.post( tap: .cghidEventTap )
		Thread.sleep( forTimeInterval: 0.02 )
	}

}
