import Foundation
import IOKit

/// Thin AppleSMC wrapper. Root-only for writes.
final class SMC {

	// Layout must match the kernel's SMCParamStruct (80 bytes)
	private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
	private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
	private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }
	private typealias Bytes32 = ( UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
	                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8 )

	private struct Param {
		var key: UInt32 = 0
		var vers = Version()
		var pLimit = PLimit()
		var keyInfo = KeyInfo()
		var padding: UInt16 = 0
		var result: UInt8 = 0
		var status: UInt8 = 0
		var data8: UInt8 = 0
		var data32: UInt32 = 0
		var bytes: Bytes32 = ( 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 )
	}

	private enum Cmd: UInt8 { case readBytes = 5, writeBytes = 6, readKeyInfo = 9 }

	private var conn: io_connect_t = 0

	init?() {
		precondition( MemoryLayout<Param>.size == 80, "SMC struct layout drifted" )
		let service = IOServiceGetMatchingService( kIOMainPortDefault, IOServiceMatching( "AppleSMC" ) )
		guard service != 0 else { return nil }
		defer { IOObjectRelease( service ) }
		guard IOServiceOpen( service, mach_task_self_, 0, &conn ) == kIOReturnSuccess else { return nil }
	}

	deinit { IOServiceClose( conn ) }

	private func call( _ input: inout Param ) -> Param? {
		var output = Param()
		var size = MemoryLayout<Param>.size
		let r = IOConnectCallStructMethod( conn, 2, &input, MemoryLayout<Param>.size, &output, &size )
		return r == kIOReturnSuccess && output.result == 0 ? output : nil
	}

	private static func fourCC( _ s: String ) -> UInt32 { s.utf8.reduce( 0 ) { $0 << 8 | UInt32( $1 ) } }

	private func info( _ key: String ) -> KeyInfo? {
		var p = Param(); p.key = Self.fourCC( key ); p.data8 = Cmd.readKeyInfo.rawValue
		return call( &p )?.keyInfo
	}

	func has( _ key: String ) -> Bool { info( key ) != nil }

	/// Lowercase hex of the key's bytes, e.g. "00000000". Nil if the key is missing.
	func read( _ key: String ) -> String? {
		guard let ki = info( key ) else { return nil }
		var p = Param(); p.key = Self.fourCC( key ); p.keyInfo.dataSize = ki.dataSize; p.data8 = Cmd.readBytes.rawValue
		guard let out = call( &p ) else { return nil }
		return withUnsafeBytes( of: out.bytes ) { $0.prefix( Int( ki.dataSize ) ).map { String( format: "%02x", $0 ) }.joined() }
	}

	/// `hex` is e.g. "01000000"; length must match the key's size.
	@discardableResult
	func write( _ key: String, hex: String ) -> Bool {
		guard let ki = info( key ), hex.count == Int( ki.dataSize ) * 2 else { return false }
		var p = Param(); p.key = Self.fourCC( key ); p.keyInfo = ki; p.data8 = Cmd.writeBytes.rawValue
		var bytes = [ UInt8 ]()
		var idx = hex.startIndex
		while idx < hex.endIndex {
			let next = hex.index( idx, offsetBy: 2 )
			guard let b = UInt8( hex[ idx..<next ], radix: 16 ) else { return false }
			bytes.append( b ); idx = next
		}
		withUnsafeMutableBytes( of: &p.bytes ) { raw in for ( i, b ) in bytes.enumerated() { raw[ i ] = b } }
		return call( &p ) != nil
	}

}
