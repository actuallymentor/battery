import Foundation

/// v1 install footprint (shell CLI, sudoers entry, LaunchAgent). Removed on first v2 launch after the user confirms.
enum Legacy {

	/// Every path v1's setup.sh / battery.sh can create for this user. Nil entries only exist when `home` is known.
	private static func paths( home: String ) -> [ String ] { [
		"/usr/local/co.palokaj.battery",
		"/usr/local/bin/battery",
		"/usr/local/bin/smc",
		"/private/etc/sudoers.d/battery",
		"\( home )/.battery",
		"\( home )/Library/LaunchAgents/battery.plist",
	] }

	static func home( uid: uid_t ) -> String? { getpwuid( uid ).map { String( cString: $0.pointee.pw_dir ) } }

	/// Display names of what is still installed.
	static func found( uid: uid_t ) -> [ String ] {
		guard let home = home( uid: uid ) else { return [] }
		return paths( home: home ).filter { isV1( $0 ) }
	}

	/// /usr/local/bin/battery could in theory be something else: only count it when it points into v1's folder.
	private static func isV1( _ path: String ) -> Bool {
		let fm = FileManager.default
		guard fm.fileExists( atPath: path ) || ( try? fm.destinationOfSymbolicLink( atPath: path ) ) != nil else { return false }
		if path.hasPrefix( "/usr/local/bin/" ) {
			guard let dest = try? fm.destinationOfSymbolicLink( atPath: path ) else { return false }
			return dest.hasPrefix( "/usr/local/co.palokaj.battery" )
		}
		return true
	}

	static func remove( uid: uid_t ) -> [ String ] {
		guard let home = home( uid: uid ) else { return [] }

		// Stop the v1 LaunchAgent and any v1 maintain loop before deleting what they run from
		run( "/bin/launchctl", [ "bootout", "gui/\( uid )/com.battery.app" ] )
		run( "/usr/bin/pkill", [ "-f", "/usr/local/co.palokaj.battery" ] )

		var removed = [ String ]()
		for path in paths( home: home ) where isV1( path ) {
			if ( try? FileManager.default.removeItem( atPath: path ) ) != nil { removed.append( path ) }
		}
		return removed
	}

	@discardableResult
	private static func run( _ exe: String, _ args: [ String ] ) -> Int32 {
		let p = Process()
		p.executableURL = URL( fileURLWithPath: exe )
		p.arguments = args
		p.standardOutput = FileHandle.nullDevice
		p.standardError = FileHandle.nullDevice
		do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
	}

}
