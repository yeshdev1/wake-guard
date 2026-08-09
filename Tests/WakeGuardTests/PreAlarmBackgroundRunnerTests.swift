import Synchronization
import XCTest

@testable import WakeGuard

/// WG-088: the pre-alarm background opportunity runner. Verifies the run is **opportunistic and
/// expiration-safe** (expiration cancels the advisory work and the task still completes), that it
/// **reschedules the next opportunity at a bounded delay** (no tight loop) even when the run is
/// expired, and that it holds **no alarm authority** — a failed / cancelled run changes no alarm (it
/// has no alarm seam to change one).
/// A `Mutex`-backed `BackgroundTaskHandle` for tests: records completion and lets the test fire the
/// expiration handler the runner registered.
private final class FakeBackgroundTaskHandle: BackgroundTaskHandle {
    private struct State {
        var expiration: (@Sendable () -> Void)?
        var completed: Bool?
    }
    private let state = Mutex(State())
    private let expiresOnRegister: Bool

    init(expiresOnRegister: Bool = false) { self.expiresOnRegister = expiresOnRegister }

    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
        state.withLock { $0.expiration = handler }
        // Simulate the OS expiring instantly, before the work task is wired.
        if expiresOnRegister { handler() }
    }
    func complete(success: Bool) { state.withLock { $0.completed = success } }

    var completedSuccess: Bool? { state.withLock { $0.completed } }
    var hasExpirationHandler: Bool { state.withLock { $0.expiration != nil } }
    func triggerExpiration() { (state.withLock { $0.expiration })?() }
}

private actor CancellationObserver {
    private(set) var cancelled = false
    func markCancelled() { cancelled = true }
}

final class PreAlarmBackgroundRunnerTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Bounded reschedule (no tight loop)

    func testNextRequestTimeIsBoundedNoTightLoop() {
        let now = self.now
        XCTAssertEqual(
            PreAlarmBackgroundRunner().nextRequestTime(after: now), now.addingTimeInterval(900))
        XCTAssertEqual(
            PreAlarmBackgroundRunner(config: .init(minimumReschedule: 120)).nextRequestTime(
                after: now), now.addingTimeInterval(120))
        // A too-tight or non-finite interval clamps to the safe default — never a tight loop.
        XCTAssertEqual(
            PreAlarmBackgroundRunner(config: .init(minimumReschedule: 1)).nextRequestTime(
                after: now),
            now.addingTimeInterval(900))
        XCTAssertEqual(
            PreAlarmBackgroundRunner(config: .init(minimumReschedule: .nan)).nextRequestTime(
                after: now), now.addingTimeInterval(900))
    }

    // MARK: - Lifecycle

    func testRunReschedulesThenCompletesSuccessfullyWhenWorkFinishes() async {
        let handle = FakeBackgroundTaskHandle()
        let scheduled = Mutex<Date?>(nil)
        let now = self.now

        await PreAlarmBackgroundRunner().run(
            handle, now: now, scheduleNext: { date in scheduled.withLock { $0 = date } }, work: {})

        XCTAssertEqual(
            scheduled.withLock { $0 }, now.addingTimeInterval(900),
            "the next opportunity is rescheduled at the bounded delay")
        XCTAssertEqual(handle.completedSuccess, true, "a finished run completes successfully")
    }

    func testExpirationCancelsWorkAndStillCompletesAndReschedules() async {
        let handle = FakeBackgroundTaskHandle()
        let observer = CancellationObserver()
        let scheduled = Mutex<Date?>(nil)
        let now = self.now

        async let run: Void = PreAlarmBackgroundRunner().run(
            handle, now: now,
            scheduleNext: { date in scheduled.withLock { $0 = date } },
            work: {
                while !Task.isCancelled { await Task.yield() }
                await observer.markCancelled()
            })

        // Once the runner has registered its expiration handler, fire it — the OS reclaiming the task.
        while !handle.hasExpirationHandler { await Task.yield() }
        handle.triggerExpiration()
        await run

        XCTAssertEqual(handle.completedSuccess, false, "an expired run completes unsuccessfully")
        let cancelled = await observer.cancelled
        XCTAssertTrue(cancelled, "expiration cancels the advisory work")
        XCTAssertNotNil(
            scheduled.withLock { $0 },
            "the next opportunity is still queued even when this run is expired (no alarm touched)")
    }

    func testExpirationBeforeWorkIsWiredStillCancels() async {
        // The OS expires the instant the handler is registered — before the work task is stored. The
        // race-free wiring must still cancel the work and complete unsuccessfully.
        let handle = FakeBackgroundTaskHandle(expiresOnRegister: true)
        let observer = CancellationObserver()

        await PreAlarmBackgroundRunner().run(
            handle, now: now, scheduleNext: { _ in },
            work: {
                while !Task.isCancelled { await Task.yield() }
                await observer.markCancelled()
            })

        XCTAssertEqual(handle.completedSuccess, false)
        let cancelled = await observer.cancelled
        XCTAssertTrue(cancelled, "an expiration racing task creation still cancels the work")
    }
}
