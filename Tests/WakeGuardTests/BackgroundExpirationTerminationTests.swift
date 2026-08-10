import Foundation
import Synchronization
import XCTest

@testable import WakeGuard

/// WG-229: background expiration & termination. Verifies **expiration handlers complete safely** (an expired
/// run cancels its work and completes the task, no crash), that **termination never causes a silent
/// mutation** (an interrupted external call yields `.uncertain`, never a silent apply), and that
/// **reconciliation repairs uncertainty** (the uncertain schedule is resolved on the next reconcile).
final class BackgroundExpirationTerminationTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let ids = DeterministicIDGenerator(seed: 27)

    // MARK: expiration completes safely + no partial mutation

    func testExpirationCancelsWorkAndCompletesTheTaskSafely() async {
        let handle = FakeBackgroundTaskHandle(expiresOnRegister: true)
        let observer = CancellationObserver()
        await PreAlarmBackgroundRunner().run(
            handle, now: now, scheduleNext: { _ in },
            work: {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch {
                    await observer.markCancelled()
                }
            })

        XCTAssertNotNil(
            handle.completedSuccess, "an expired task must still be completed (no hang)")
        let cancelled = await observer.cancelled
        XCTAssertTrue(cancelled, "expired work is cancelled — no partial mutation")
    }

    // MARK: interrupted external call is uncertain, repaired by reconcile

    func testInterruptedScheduleIsUncertainThenRepairedByReconciliation() async throws {
        let controller = try PersistenceController(inMemory: true)
        let alarms = CoreDataAlarmRepository(controller)
        let adapter = FakeAlarmManagerAdapter()
        let processor = AlarmCommandProcessor(
            policy: FakeAlarmPolicyEngine(), alarms: alarms,
            audit: CoreDataAuditRepository(controller),
            outbox: CoreDataOutboxRepository(controller),
            alarmManager: adapter, clock: TestClock(now: now),
            ids: DeterministicIDGenerator(seed: 5), deviceTimeZone: { .gmt })

        // The external schedule is interrupted (e.g. app killed mid-call) → uncertain, not silently applied.
        adapter.inject(.uncertain, on: .schedule)
        let alarm = try makeAlarm()
        let outcome = await processor.process(.create(alarm), from: .userInterface, by: .user)
        XCTAssertEqual(
            outcome, .uncertain, "an interrupted external call is uncertain, never a silent apply")

        // The system recovers; reconciliation repairs the uncertainty by scheduling the desired alarm.
        adapter.inject(nil, on: .schedule)
        _ = await processor.reconcile()
        XCTAssertEqual(
            adapter.currentlyScheduled.map(\.alarmID), [alarm.id],
            "reconciliation repairs the uncertain schedule")
    }

    private func makeAlarm() throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", isEnabled: true, schedule: schedule,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }
}

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
        if expiresOnRegister { handler() }
    }

    func complete(success: Bool) { state.withLock { $0.completed = success } }

    var completedSuccess: Bool? { state.withLock { $0.completed } }
}

private actor CancellationObserver {
    private(set) var cancelled = false
    func markCancelled() { cancelled = true }
}
