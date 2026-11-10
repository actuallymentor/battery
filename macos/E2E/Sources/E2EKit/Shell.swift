import Foundation

public struct Result { public let code: Int32; public let out: String; public let err: String; public var ok: Bool { code == 0 } }

/// Runs a real process and waits (killing it after `timeout`).
public func sh( _ path: String, _ args: [ String ] = [], timeout: TimeInterval = 30 ) -> Result {

	let p = Process(), o = Pipe(), e = Pipe()
	p.executableURL = URL( fileURLWithPath: path )
	p.arguments = args
	p.standardOutput = o
	p.standardError = e

	do { try p.run() } catch { return Result( code: 127, out: "", err: "\( error )" ) }

	// Drain on background queues so a chatty child can't fill the pipe and deadlock
	var out = Data(), err = Data()
	let group = DispatchGroup()
	for ( pipe, store ) in [ ( o, 0 ), ( e, 1 ) ] {
		group.enter()
		DispatchQueue.global().async {
			let d = pipe.fileHandleForReading.readDataToEndOfFile()
			if store == 0 { out = d } else { err = d }
			group.leave()
		}
	}

	let deadline = Date().addingTimeInterval( timeout )
	while p.isRunning && Date() < deadline { Thread.sleep( forTimeInterval: 0.05 ) }
	if p.isRunning { p.terminate() }
	p.waitUntilExit()
	group.wait()

	return Result( code: p.terminationStatus, out: String( decoding: out, as: UTF8.self ).trimmingCharacters( in: .whitespacesAndNewlines ), err: String( decoding: err, as: UTF8.self ).trimmingCharacters( in: .whitespacesAndNewlines ) )
}

/// Polls until `check` returns a value (not nil / not false), or times out with nil.
@discardableResult
public func eventually<T>( _ seconds: TimeInterval = 10, every: TimeInterval = 0.25, _ check: () -> T? ) -> T? {
	let deadline = Date().addingTimeInterval( seconds )
	repeat {
		if let v = check() { return v }
		Thread.sleep( forTimeInterval: every )
	} while Date() < deadline
	return nil
}
