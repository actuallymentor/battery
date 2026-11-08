import Foundation
import BatteryCore

enum DaemonError: LocalizedError {
	case unreachable
	case failed( String )

	var errorDescription: String? {
		switch self {
		case .unreachable: return "The Battery helper isn't running."
		case .failed( let m ): return m
		}
	}
}

/// Async wrapper over the daemon's XPC interface. Every call is bounded: an unregistered Mach name never errors, it just hangs.
final class DaemonClient {

	private var connection: NSXPCConnection?

	private func proxy( onError: @escaping ( Error ) -> Void ) -> BatteryDaemonXPC {
		if connection == nil {
			let c = NSXPCConnection( machServiceName: batteryDaemonName, options: .privileged )
			c.remoteObjectInterface = NSXPCInterface( with: BatteryDaemonXPC.self )
			c.invalidationHandler = { [ weak self ] in self?.connection = nil }
			c.interruptionHandler = { [ weak self ] in self?.connection = nil }
			c.resume()
			connection = c
		}
		return connection!.remoteObjectProxyWithErrorHandler( onError ) as! BatteryDaemonXPC
	}

	/// Runs one XPC call; resumes exactly once with the reply, an XPC error, or a timeout.
	func call( timeout: TimeInterval = 5, _ body: @escaping ( BatteryDaemonXPC, @escaping ( Bool, String ) -> Void ) -> Void ) async throws -> String {
		try await withCheckedThrowingContinuation { cont in
			let gate = Gate()
			func finish( _ r: Result<String, Error> ) { if gate.claim() { cont.resume( with: r ) } }

			DispatchQueue.global().asyncAfter( deadline: .now() + timeout ) { finish( .failure( DaemonError.unreachable ) ) }
			let p = proxy { _ in finish( .failure( DaemonError.unreachable ) ) }
			body( p ) { ok, text in finish( ok ? .success( text ) : .failure( DaemonError.failed( text ) ) ) }
		}
	}

	// MARK: Typed calls

	func snapshot() async throws -> BatteryStatus {
		let json = try await call { $0.snapshot( reply: $1 ) }
		guard let s = BatteryStatus.decode( json ) else { throw DaemonError.failed( "Unreadable status" ) }
		return s
	}

	func maintain( _ target: MaintainTarget, force: Bool ) async throws { _ = try await call { $0.maintain( target.persisted, forceDischarge: force, reply: $1 ) } }
	func stopMaintain() async throws { _ = try await call { $0.stopMaintain( reply: $1 ) } }
	func charge( _ percent: Int ) async throws { _ = try await call { $0.charge( percent, reply: $1 ) } }
	func discharge( _ percent: Int ) async throws { _ = try await call { $0.discharge( percent, reply: $1 ) } }
	func calibrate() async throws { _ = try await call { $0.calibrate( reply: $1 ) } }
	func recover() async throws { _ = try await call { $0.recover( reply: $1 ) } }
	func setSchedule( _ days: Int ) async throws { _ = try await call { $0.setSchedule( days, reply: $1 ) } }
	func resetAll() async throws { _ = try await call { $0.resetAll( reply: $1 ) } }

	func legacyFound() async throws -> [ String ] {
		try await call { $0.legacyFound( reply: $1 ) }.split( separator: "," ).map( String.init )
	}

	func removeLegacy() async throws { _ = try await call( timeout: 20 ) { $0.removeLegacy( reply: $1 ) } }

}

/// One-shot latch so a continuation is never resumed twice (reply vs error vs timeout).
private final class Gate {
	private let lock = NSLock()
	private var claimed = false
	func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if claimed { return false }; claimed = true; return true }
}
