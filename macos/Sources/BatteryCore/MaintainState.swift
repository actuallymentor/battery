import Foundation

/// The whole `maintain` loop, pure: the remembered target (kept while switched off, so the app's slider and a reboot agree),
/// the refilling / held-since latches, the firmware and force-discharge branches. Readings in, `Intent`s out; the daemon
/// only runs them. Every rule that used to live in the root daemon is testable here.
public struct MaintainState: Equatable, Sendable {

	/// What the loop sees each tick
	public struct Reading: Equatable, Sendable {
		public var percent: Int
		public var voltage: Double?
		public var chargingEnabled: Bool?
		public var acAttached: Bool
		/// The adapter is cut by us right now
		public var adapterCut: Bool
		public var lidClosed: Bool
		/// Firmware backend: is our band still in the SMC? Nil elsewhere.
		public var firmwareActive: Bool?

		public init( percent: Int, voltage: Double? = nil, chargingEnabled: Bool?, acAttached: Bool, adapterCut: Bool = false, lidClosed: Bool = false, firmwareActive: Bool? = nil ) {
			self.percent = percent
			self.voltage = voltage
			self.chargingEnabled = chargingEnabled
			self.acAttached = acAttached
			self.adapterCut = adapterCut
			self.lidClosed = lidClosed
			self.firmwareActive = firmwareActive
		}
	}

	public let backend: SMCCapabilities.Backend

	/// Remembered even while `enabled` is false: the slider shows it, the switch turns it back on
	public private( set ) var target: MaintainTarget?
	public private( set ) var force = false
	public private( set ) var enabled = false

	/// A job owns the hardware: keep everything, do nothing until `resume` or `release`
	public private( set ) var suspended = false

	/// We resumed charging below `lower` and have not reached `upper` yet (#475: plugging in inside the band must not charge to the top)
	public private( set ) var refilling = false

	/// When we last asked the hardware to hold. Used to judge "requested vs effective" after a grace period.
	public private( set ) var heldSince: Date?

	public init( backend: SMCCapabilities.Backend ) { self.backend = backend }

	/// The band being held right now, nil when off. What `status` and the CLI report.
	public var active: MaintainTarget? { enabled ? target : nil }

	// MARK: Changes

	/// New target, or the same one switched on/off. Returns what to do to the hardware right away.
	public mutating func set( _ t: MaintainTarget, force: Bool, enabled: Bool, reading r: Reading ) -> [ Intent ] {
		// A raised limit means "charge up to it"; a plain switch-on inside the band holds (plug-in rule). Firmware does this itself.
		let raised = enabled && backend != .firmwareLimit && Controller.refillsAfterRetarget( from: active, to: t, percent: r.percent )
		let wasHolding = self.enabled && !suspended

		target = t
		self.force = force
		self.enabled = enabled
		refilling = raised
		heldSince = nil

		var out: [ Intent ] = []
		if !enabled { return wasHolding ? [ .resetAll ] : [] }     // switching off: stock charging, unless a job owns the hardware; already off: nothing to touch
		suspended = false
		if !force, r.adapterCut { out.append( .adapter( on: true ) ) }   // a replaced job may have left it cut; only force-discharge keeps it
		if raised { out.append( .charging( on: true, holdAtLevel: nil ) ) }
		return out
	}

	/// `maintain stop`: hardware back to stock unless a job runs (that one owns it), the target is kept.
	public mutating func stop() -> [ Intent ] {
		enabled = false
		heldSince = nil
		return suspended ? [] : [ .resetAll ]
	}

	/// A job (charge/discharge/calibrate) takes over charging.
	public mutating func suspend() { suspended = true }

	/// The job was replaced by something that now owns the hardware (new target, manual override): just stop waiting for it.
	public mutating func release() { suspended = false }

	/// Back after a job. Switched off: `restoring` hands charging back to macOS, otherwise leave it as the job set it.
	public mutating func resume( restoring: Bool, reading r: Reading ) -> [ Intent ] {
		suspended = false
		if enabled, let target { return set( target, force: force, enabled: true, reading: r ) }
		return restoring ? [ .resetAll ] : []
	}

	// MARK: Loop

	public mutating func tick( _ r: Reading, now: Date = Date() ) -> [ Intent ] {
		guard enabled, !suspended, let target else { return [] }
		var out: [ Intent ] = []

		// Firmware: the limit lives in the SMC. Just make sure it is still there.
		if backend == .firmwareLimit, case .level( let lower, let upper ) = target {
			if upper < 100, r.firmwareActive == false { out.append( .firmwareLimit( upper: upper, lower: lower ) ) }
			if heldSince == nil, r.percent >= upper { heldSince = now }
			return out
		}

		if force, case .level( _, let upper ) = target {
			let want = Controller.forceDischargeCut( percent: r.percent, upper: upper, acAttached: r.acAttached, currentlyCut: r.adapterCut, lidClosed: r.lidClosed )
			if want != r.adapterCut { out.append( .adapter( on: !want ) ) }
		}

		let state = BatteryState( percent: r.percent, voltage: r.voltage, chargingEnabled: r.chargingEnabled, acAttached: r.acAttached, refilling: refilling )
		let d = Controller.decide( target, state )
		if let latch = d.refilling { refilling = latch }
		if let led = d.led { out.append( .led( led ) ) }

		switch d.action {
		case .enableCharging:
			out.append( .charging( on: true, holdAtLevel: nil ) )
			heldSince = nil
		case .disableCharging:
			out.append( .charging( on: false, holdAtLevel: r.percent ) )
			heldSince = now
		case .none:
			if r.chargingEnabled == false, heldSince == nil { heldSince = now }
		}
		return out
	}

	/// Observed effect problem, for the UI. Nil = fine or unknown.
	public func warning( _ r: Reading, isCharging: Bool?, amperage: Int?, now: Date = Date() ) -> String? {
		guard active != nil else { return nil }
		return Controller.effectWarning( heldFor: heldSince.map { now.timeIntervalSince( $0 ) }, chargingEnabled: r.chargingEnabled,
		                                 acAttached: r.acAttached, isCharging: isCharging, amperage: amperage )
	}

	// MARK: Persistence. One line, v1-shaped: "80 --force-discharge --off"

	public var persisted: String? {
		target.map { $0.persisted + ( force ? " --force-discharge" : "" ) + ( enabled ? "" : " --off" ) }
	}

	public static func parse( _ line: String ) -> ( target: MaintainTarget, force: Bool, enabled: Bool )? {
		let words = line.split( separator: " " ).map( String.init )
		let setting = words.filter { !$0.hasPrefix( "--" ) }.joined( separator: " " )
		return ( try? MaintainTarget( persisted: setting ) ).map { ( $0, words.contains( "--force-discharge" ), !words.contains( "--off" ) ) }
	}

}
