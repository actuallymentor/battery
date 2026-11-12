import E2EKit
import XCTest

/// Base for every e2e test: a known-good Mac in, the same Mac out. Real helper, real SMC, real charging state.
class E2ECase: XCTestCase {

	/// Whether this Mac can cut the adapter (tahoe/legacy backends). Decides which behaviors exist to test.
	/// Lid closed (clamshell): force discharge must leave the adapter alone then
	static var lidClosed: Bool { sh( "/usr/sbin/ioreg", [ "-r", "-c", "IOPMrootDomain", "-d1" ] ).out.contains( "\"AppleClamshellState\" = Yes" ) }

	static var canCutAdapter: Bool { { let p = CLI.battery( "probe" ).out; return p.contains( "CHIE=true" ) || p.contains( "CH0I=true" ) || p.contains( "CH0J=true" ) }() }

	override func setUp() {
		continueAfterFailure = false
		XCTAssertTrue( FileManager.default.isExecutableFile( atPath: CLI.path ), "No battery CLI at \( CLI.path ). Run scripts/e2e.sh, it installs the build under test." )
		XCTAssertTrue( CLI.battery( "version" ).ok )
		let status = CLI.battery( "status" )
		XCTAssertTrue( status.ok, "Helper not answering: \( status.err.isEmpty ? status.out : status.err )" )
		CLI.restore()
	}

	override func tearDown() { CLI.restore() }

}
