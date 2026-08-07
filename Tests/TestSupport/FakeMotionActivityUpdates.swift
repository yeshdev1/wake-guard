import Foundation

@testable import WakeGuard

/// A controllable `MotionActivityUpdates` for tests (WG-064): records the handler so a test can push
/// a recorded trace of readings (or a nil reading) and observe start/stop, without CoreMotion.
/// Thread-safe via a lock because the adapter may invoke `stop` from stream termination on a
/// different task than the one driving `emit`.
final class FakeMotionActivityUpdates: MotionActivityUpdates, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (MotionActivityReading?) -> Void)?
    private var startCount = 0
    private var stopCount = 0

    func start(handler: @escaping @Sendable (MotionActivityReading?) -> Void) {
        lock.lock()
        self.handler = handler
        startCount += 1
        lock.unlock()
    }

    func stop() {
        lock.lock()
        stopCount += 1
        lock.unlock()
    }

    /// Deliver one reading (or nil) to the started stream.
    func emit(_ reading: MotionActivityReading?) { currentHandler()?(reading) }

    var started: Bool { lock.lock(); defer { lock.unlock() }; return startCount > 0 }
    var stopped: Int { lock.lock(); defer { lock.unlock() }; return stopCount }

    private func currentHandler() -> (@Sendable (MotionActivityReading?) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }
}
