// swift-tools-version:5.9
import PackageDescription

// Pure logic shared by the app, daemon and CLI. No IOKit/AppKit: builds and tests on Linux.
let package = Package(
	name: "BatteryCore",
	platforms: [ .macOS( .v14 ) ],
	products: [ .library( name: "BatteryCore", targets: [ "BatteryCore" ] ) ],
	targets: [
		.target( name: "BatteryCore" ),
		.testTarget( name: "BatteryCoreTests", dependencies: [ "BatteryCore" ] ),
	]
)
