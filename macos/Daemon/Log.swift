import Foundation

/// Daemon log: stderr + /Library/Logs file (readable by `battery logs`). Truncated past 1 MB.
func log( _ message: String ) {
	let line = "\( ISO8601DateFormatter().string( from: Date() ) ) \( message )\n"
	FileHandle.standardError.write( Data( line.utf8 ) )

	let url = URL( fileURLWithPath: batteryLogPath )
	let fm = FileManager.default
	if let size = ( try? fm.attributesOfItem( atPath: batteryLogPath ) )?[ .size ] as? Int, size > 1_000_000 { try? fm.removeItem( at: url ) }
	if !fm.fileExists( atPath: batteryLogPath ) { fm.createFile( atPath: batteryLogPath, contents: nil, attributes: [ .posixPermissions: 0o644 ] ) }
	if let h = try? FileHandle( forWritingTo: url ) { h.seekToEndOfFile(); h.write( Data( line.utf8 ) ); try? h.close() }
}
