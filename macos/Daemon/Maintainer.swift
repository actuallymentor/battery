import Foundation
import BatteryCore

/// `battery maintain`: re-evaluates every tick and flips charging via the SMC. Survives reboots (persisted target).
final class Maintainer {

	private let smc: SMC
	private let caps: SMCCapabilities
	private let file = URL( fileURLWithPath: "/var/db/co.palokaj.battery/maintain" )
	private var timer: Timer?
	private var adapterCut = false

	private( set ) var target: MaintainTarget?
	private var forceDischarge = false

	init( smc: SMC, caps: SMCCapabilities ) {
		self.smc = smc
		self.caps = caps
		resume()
	}

	/// Pick up the persisted target after a reboot / daemon restart.
	private func resume() {
		guard let raw = try? String( contentsOf: file, encoding: .utf8 ) else { return }
		let force = raw.contains( "--force-discharge" )
		let setting = raw.replacingOccurrences( of: " --force-discharge", with: "" ).trimmingCharacters( in: .whitespacesAndNewlines )
		if let t = try? MaintainTarget( persisted: setting ) { start( t, force: force, persist: false ) }
	}

	func start( _ t: MaintainTarget, force: Bool, persist: Bool = true ) {
		target = t
		forceDischarge = force
		if persist {
			try? FileManager.default.createDirectory( at: file.deletingLastPathComponent(), withIntermediateDirectories: true )
			try? ( t.persisted + ( force ? " --force-discharge" : "" ) ).write( to: file, atomically: true, encoding: .utf8 )
		}
		timer?.invalidate()
		timer = Timer.scheduledTimer( withTimeInterval: Controller.maintainPollInterval, repeats: true ) { [ weak self ] _ in self?.tick() }
		tick()
	}

	/// Stop and hand charging back to macOS.
	func stop() {
		timer?.invalidate(); timer = nil
		target = nil
		try? FileManager.default.removeItem( at: file )
		restore()
	}

	/// Charging on, adapter on.
	private func restore() {
		SMCPlan.charging( true, caps )?.forEach { smc.write( $0.key, hex: $0.hex ) }
		if adapterCut { SMCPlan.adapter( on: true, caps ).forEach { smc.write( $0.key, hex: $0.hex ) }; adapterCut = false }
	}

	private func tick() {
		guard let target, let reading = Power.read() else { return }

		let state = BatteryState( percent: reading.snapshot.percent, voltage: reading.voltage,
		                          chargingEnabled: SMCPlan.chargingEnabled( caps ) { smc.read( $0 ) },
		                          acAttached: reading.snapshot.acAttached )

		// --force-discharge: above the band on AC, cut the adapter until we are back inside it
		if forceDischarge, case .level( _, let upper ) = target {
			let over = state.percent > upper && state.acAttached
			if over != adapterCut {
				SMCPlan.adapter( on: !over, caps ).forEach { smc.write( $0.key, hex: $0.hex ) }
				adapterCut = over
			}
		}

		switch Controller.decide( target, state ).action {
		case .enableCharging: SMCPlan.charging( true, caps )?.forEach { smc.write( $0.key, hex: $0.hex ) }
		case .disableCharging: SMCPlan.charging( false, caps )?.forEach { smc.write( $0.key, hex: $0.hex ) }
		case .none: break
		}
	}

}
