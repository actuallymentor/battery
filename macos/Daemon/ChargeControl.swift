import Foundation
import BatteryCore

/// The only place that writes SMC keys. Knows which backend this Mac has, verifies every write by reading it back,
/// and rolls the firmware limit back when a sequence fails half way (a half-written limit can drain the pack).
final class ChargeControl {

	let smc: SMC
	let caps: SMCCapabilities
	var backend: SMCCapabilities.Backend { caps.backend }

	init( smc: SMC, caps: SMCCapabilities ) {
		self.smc = smc
		self.caps = caps
	}

	// MARK: Reads

	var chargingEnabled: Bool? { SMCPlan.chargingEnabled( caps ) { smc.read( $0 ) } }
	var adapterCut: Bool? { SMCPlan.discharging( caps ) { smc.read( $0 ) } }

	// MARK: Writes

	/// Write in order, read each back. False (and logged) on the first mismatch.
	@discardableResult
	func apply( _ writes: [ SMCWrite ]? ) -> Bool {
		guard let writes else { return false }
		for w in writes {
			guard smc.write( w.key, hex: w.hex ) else { log( "SMC write failed: \( w.key )=\( w.hex )" ); return false }
			if let got = smc.read( w.key ), got != w.hex { log( "SMC verify failed: \( w.key ) wrote \( w.hex ) read \( got )" ); return false }
		}
		return true
	}

	/// Allow or hold charging. On the firmware backend "hold" freezes the limit at `level`.
	@discardableResult
	func charging( _ on: Bool, level: Int? = nil ) -> Bool {
		let ok = apply( SMCPlan.charging( on, caps, level: level ) )
		if !ok && backend == .firmwareLimit { apply( SMCPlan.firmwareReset ) }   // never leave a half-written limit
		return ok
	}

	/// We cut the adapter and have not restored it. Anything that can cut (maintain, jobs) goes through here, so one flag covers all.
	private( set ) var adapterCutByUs = false

	@discardableResult
	func adapter( on: Bool ) -> Bool {
		guard caps.canCutAdapter else { return false }
		let ok = apply( SMCPlan.adapter( on: on, caps ) )
		if ok { adapterCutByUs = !on }
		return ok
	}

	/// Firmware backend: hand a band to the firmware, which then enforces it by itself (also asleep and before login).
	@discardableResult
	func firmwareLimit( upper: Int, lower: Int ) -> Bool {
		guard backend == .firmwareLimit else { return false }
		guard upper < 100 else { return apply( SMCPlan.firmwareReset ) }     // 100 = no limit
		let ok = apply( SMCPlan.firmwareLimit( upper: upper, lower: lower ) )
		if !ok { apply( SMCPlan.firmwareReset ) }
		return ok
	}

	/// Firmware limit still what we set? (Firmware or macOS can clear it, e.g. after an update.)
	func firmwareLimitActive( upper: Int ) -> Bool {
		smc.read( "bfF0" ) == "02" && smc.read( "bfD0" ) == SMCPlan.le32( upper )
	}

	/// Everything back to stock: charging on, adapter on, firmware limit off.
	func resetAll() {
		if backend == .firmwareLimit { apply( SMCPlan.firmwareReset ) }
		else { charging( true ) }
		if caps.canCutAdapter { adapter( on: true ) }
	}

	// MARK: Unsupported

	var unsupportedMessage: String {
		"This Mac exposes no charge-limit control (looked for CHTE, CH0B/CH0C, bfD0/bfE0/bfF0, CHIE). Found: \( caps.keys.sorted().joined( separator: " " ) )."
	}

}
