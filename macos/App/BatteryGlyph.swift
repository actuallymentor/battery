import AppKit

/// Menu bar battery with a continuous fill (SF Symbols only has five fixed levels).
/// A template image: macOS tints it for light, dark and the highlighted menu bar.
enum BatteryGlyph {

	private static let size = NSSize( width: 25, height: 12 )

	/// `percent` 0...100. `charging` adds a bolt: carved out of the fill, solid on the empty part.
	static func image( percent: Int, charging: Bool, paused: Bool = false ) -> NSImage {

		let image = NSImage( size: size, flipped: false ) { _ in

			// Body and terminal nub
			let body = NSRect( x: 0.5, y: 0.5, width: 21.5, height: 11 )
			let outline = NSBezierPath( roundedRect: body, xRadius: 3, yRadius: 3 )
			outline.lineWidth = 1
			NSColor.black.withAlphaComponent( 0.55 ).setStroke()
			outline.stroke()
			NSColor.black.withAlphaComponent( 0.55 ).setFill()
			NSBezierPath( roundedRect: NSRect( x: 23, y: 4, width: 1.8, height: 4 ), xRadius: 0.9, yRadius: 0.9 ).fill()

			// Fill: inset 1.5pt, width follows the percentage (at least a sliver above 0)
			let inner = body.insetBy( dx: 1.5, dy: 1.5 )
			let fraction = CGFloat( min( max( percent, 0 ), 100 ) ) / 100
			let width = percent > 0 ? max( inner.width * fraction, 2 ) : 0
			if width > 0 {
				NSColor.black.setFill()
				NSBezierPath( roundedRect: NSRect( x: inner.minX, y: inner.minY, width: width, height: inner.height ), xRadius: 1.6, yRadius: 1.6 ).fill()
			}

			if charging || paused, let bolt = NSImage( systemSymbolName: paused ? "pause.fill" : "bolt.fill", accessibilityDescription: nil ) {
				let boltRect = NSRect( x: body.midX - 4.5, y: body.midY - 5, width: 9, height: 10 )
				let filled = NSRect( x: inner.minX, y: inner.minY, width: width, height: inner.height )
				let empty = NSRect( x: inner.minX + width, y: inner.minY, width: inner.width - width, height: inner.height )

				// Over the fill the bolt is carved out; over the empty part it is drawn solid. Either way it reads at any level.
				NSGraphicsContext.saveGraphicsState()
				NSBezierPath( rect: filled ).addClip()
				bolt.draw( in: boltRect, from: .zero, operation: .destinationOut, fraction: 1 )
				NSGraphicsContext.restoreGraphicsState()

				NSGraphicsContext.saveGraphicsState()
				NSBezierPath( rect: empty ).addClip()
				bolt.draw( in: boltRect, from: .zero, operation: .sourceOver, fraction: 1 )
				NSGraphicsContext.restoreGraphicsState()
			}
			return true
		}
		image.isTemplate = true
		return image
	}

}
