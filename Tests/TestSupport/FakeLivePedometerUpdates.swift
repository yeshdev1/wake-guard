import Foundation

@testable import WakeGuard

/// A controllable `LivePedometerUpdates` for tests (WG-063): it records the handler so a test can
/// push a recorded trace of readings (or a terminal error) and observe start/stop, all without
/// CoreMotion. Thread-safe via a lock because the adapter may invoke `stop` from stream termination
/// on a different task than the one driving `emit`.
final class FakeLivePedometerUpdates: LivePedometerUpdates, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (PedometerReading?, Error?) -> Void)?
    private var startCount = 0
    private var stopCount = 0
    private var lastStart: Date?

    func start(from start: Date, handler: @escaping @Sendable (PedometerReading?, Error?) -> Void) {
        lock.lock()
        self.handler = handler
        lastStart = start
        startCount += 1
        lock.unlock()
    }

    func stop() {
        lock.lock()
        stopCount += 1
        lock.unlock()
    }

    // MARK: - Test drivers / observers

    /// Deliver one reading to the started stream.
    func emit(_ reading: PedometerReading) { currentHandler()?(reading, nil) }

    /// Deliver a terminal error to the started stream.
    func emitError(_ error: Error) { currentHandler()?(nil, error) }

    var started: Bool { lock.lock(); defer { lock.unlock() }; return startCount > 0 }
    var stopped: Int { lock.lock(); defer { lock.unlock() }; return stopCount }
    var startedFrom: Date? { lock.lock(); defer { lock.unlock() }; return lastStart }

    private func currentHandler() -> (@Sendable (PedometerReading?, Error?) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }
}
