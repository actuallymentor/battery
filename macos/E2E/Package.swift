// swift-tools-version:5.9
import PackageDescription

// End-to-end suites. Real Mac, real helper, real signed Battery.app: no mocks, no stubs, never runs in CI.
// Separate package so `swift test` in macos/ stays a Linux-friendly pure-logic run. Driven by scripts/e2e.sh.
let package = Package(
	name: "BatteryE2E",
	platforms: [ .macOS( .v14 ) ],
	dependencies: [ .package( path: ".." ) ],
	targets: [
		.target( name: "E2EKit", dependencies: [ .product( name: "BatteryCore", package: "macos" ) ] ),
		.executableTarget( name: "axdump", dependencies: [ "E2EKit" ] ),
		.testTarget( name: "E2ETests", dependencies: [ "E2EKit" ] ),
	]
)
