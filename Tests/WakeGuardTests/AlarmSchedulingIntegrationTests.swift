import XCTest

@testable import WakeGuard

/// WG-030: end-to-end integration of the schedule / cancel / snooze paths through the
/// command processor → adapter → persistence, exercising **every injected failure**, real
/// **cancellation races**, and the **safe persisted outcome** each leaves (#10). Happy
/// paths for create/enable/disable/update are also covered by `AlarmCommandProcessorTests`
/// (WG-027); this suite adds the failure matrix on *cancel*, the remaining schedule errors,
/// Task-cancellation races on both operations, and the occurrence-command safe contract.
final class AlarmSchedulingIntegrationTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 30)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Fixture {
        let processor: AlarmCommandProcessor
        let alarms: CoreDataAlarmRepository
        let audit: CoreDataAuditRepository
        let outbox: CoreDataOutboxRepository
        let adapter: FakeAlarmManagerAdapter
    }

    private func makeFixture() throws -> Fixture {
        let controller = try PersistenceController(inMemory: true)
        let alarms = CoreDataAlarmRepository(controller)
        let audit = CoreDataAuditRepository(controller)
        let outbox = CoreDataOutboxRepository(controller)
        let adapter = FakeAlarmManagerAdapter()
        let processor = AlarmCommandProcessor(
            policy: FakeAlarmPolicyEngine(), alarms: alarms, audit: audit, outbox: outbox,
            alarmManager: adapter, clock: TestClock(now: now),
            ids: DeterministicIDGenerator(seed: 27), deviceTimeZone: { .gmt })
        return Fixture(
            processor: processor, alarms: alarms, audit: audit, outbox: outbox, adapter: adapter)
    }

    private func makeAlarm(enabled: Bool = true) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", isEnabled: enabled, schedule: schedule,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    // MARK: - Happy-path anchors (full persisted outcome)

    func testScheduleHappyPathAppliesEverywhere() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()

        let outcome = await fixture.processor.process(
            .create(alarm), from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .applied)
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored, alarm)
        XCTAssertEqual(fixture.adapter.scheduledRequests.map(\.alarmID), [alarm.id])
        let unresolved = try await fixture.outbox.unresolvedEntries()
        XCTAssertTrue(unresolved.isEmpty, "an applied schedule leaves no unresolved outbox entry")
        let events = try await fixture.audit.events(forAlarm: alarm.id)
        XCTAssertEqual(events.map(\.outcome), [.succeeded])
    }

    func testCancelHappyPathAppliesEverywhere() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)

        let outcome = await fixture.processor.process(
            .disable(alarm.id), from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(fixture.adapter.cancelledAlarmIDs, [alarm.id])
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored?.isEnabled, false)
        let unresolved = try await fixture.outbox.unresolvedEntries()
        XCTAssertTrue(unresolved.isEmpty, "an applied cancel leaves no unresolved outbox entry")
    }

    // MARK: - Injected-failure matrix on SCHEDULE

    func testScheduleNotAuthorizedFailsAndPreservesLocalAlarm() async throws {
        try await assertScheduleFailurePreservesLocal(.notAuthorized)
    }

    func testScheduleUnavailableFailsAndPreservesLocalAlarm() async throws {
        try await assertScheduleFailurePreservesLocal(.unavailable)
    }

    func testScheduleFailedFailsAndPreservesLocalAlarm() async throws {
        try await assertScheduleFailurePreservesLocal(.failed(reason: "system busy"))
    }

    private func assertScheduleFailurePreservesLocal(_ error: AlarmManagerError) async throws {
        let fixture = try makeFixture()
        fixture.adapter.inject(error, on: .schedule)
        let alarm = try makeAlarm()

        let outcome = await fixture.processor.process(
            .create(alarm), from: .userInterface, by: .user)

        guard case .failed = outcome else {
            return XCTFail("expected .failed for \(error), got \(outcome)")
        }
        // #10: a failed external schedule must not drop the locally-saved alarm.
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored, alarm)
        XCTAssertTrue(
            fixture.adapter.scheduledRequests.isEmpty, "a failed schedule did not apply system-side"
        )
        // The audit records the *local* save as succeeded (#46 — the alarm is durably
        // persisted); the external schedule failure lives in the outbox, not the audit
        // (WG-027's local/external split). The failed op is terminal, so it leaves no
        // dangling non-terminal outbox entry — the enabled-but-unscheduled alarm is
        // re-armed by ground-truth reconciliation (WG-029), not an outbox retry.
        let events = try await fixture.audit.events(forAlarm: alarm.id)
        XCTAssertEqual(events.map(\.outcome), [.succeeded])
        let unresolved = try await fixture.outbox.unresolvedEntries()
        XCTAssertTrue(unresolved.isEmpty, "a definite failure is terminal, not left pending")
    }

    // MARK: - Injected-failure matrix on CANCEL

    func testCancelUncertainLeavesLocalDisabledAndOutboxUncertain() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        fixture.adapter.inject(.uncertain, on: .cancel)

        let outcome = await fixture.processor.process(
            .disable(alarm.id), from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .uncertain)
        // #10: local disable is applied; the uncertain cancel is left for reconciliation,
        // and the system may still hold the alarm (never assumed cancelled).
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored?.isEnabled, false)
        let unresolved = try await fixture.outbox.unresolvedEntries()
        XCTAssertEqual(unresolved.map(\.status), [.uncertain])
        let system = try await fixture.adapter.scheduledAlarms()
        XCTAssertEqual(system.map(\.alarmID), [alarm.id], "the system alarm is not assumed gone")
    }

    func testCancelFailedLeavesLocalDisabled() async throws {
        try await assertCancelFailureLeavesLocalDisabled(.failed(reason: "busy"))
    }

    func testCancelNotAuthorizedLeavesLocalDisabled() async throws {
        try await assertCancelFailureLeavesLocalDisabled(.notAuthorized)
    }

    private func assertCancelFailureLeavesLocalDisabled(_ error: AlarmManagerError) async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        fixture.adapter.inject(error, on: .cancel)

        let outcome = await fixture.processor.process(
            .disable(alarm.id), from: .userInterface, by: .user)

        guard case .failed = outcome else {
            return XCTFail("expected .failed for \(error), got \(outcome)")
        }
        // #10: the local intent (disabled) is preserved even though the system cancel failed.
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored?.isEnabled, false)
        let unresolved = try await fixture.outbox.unresolvedEntries()
        XCTAssertTrue(unresolved.isEmpty, "a hard-failed cancel is terminal, not left pending")
    }

    func testUpdateRescheduleFailurePreservesUpdatedLocalAlarm() async throws {
        // The external-failure handling is shared by create/update; verify a failure during
        // an *update*'s reschedule still preserves the updated local alarm (#10).
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        fixture.adapter.inject(.failed(reason: "busy"), on: .schedule)

        var updated = alarm
        updated.label = "renamed"
        updated.revision = 1
        updated.updatedAt = now
        let outcome = await fixture.processor.process(
            .update(updated), from: .userInterface, by: .user)

        guard case .failed = outcome else {
            return XCTFail("expected .failed, got \(outcome)")
        }
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(
            stored?.label, "renamed",
            "the local update is preserved despite the failed reschedule (#10)")
    }

    // MARK: - Cancellation races

    func testScheduleCancellationRaceIsUncertainAndLeavesOutbox() async throws {
        let controller = try PersistenceController(inMemory: true)
        let alarms = CoreDataAlarmRepository(controller)
        let outbox = CoreDataOutboxRepository(controller)
        let processor = makeProcessor(alarms: alarms, outbox: outbox, controller: controller)
        let alarm = try makeAlarm()

        let task = Task {
            await processor.process(.create(alarm), from: .userInterface, by: .user)
        }
        task.cancel()
        let outcome = await task.value

        XCTAssertEqual(
            outcome, .uncertain, "a cancelled external call is uncertain, not assumed undone")
        let stored = try await alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored, alarm, "the local alarm is preserved (#10)")
        let unresolved = try await outbox.unresolvedEntries()
        XCTAssertEqual(unresolved.map(\.status), [.uncertain], "left for reconciliation")
    }

    func testCancelCancellationRaceIsUncertain() async throws {
        let controller = try PersistenceController(inMemory: true)
        let alarms = CoreDataAlarmRepository(controller)
        let outbox = CoreDataOutboxRepository(controller)
        let processor = makeProcessor(alarms: alarms, outbox: outbox, controller: controller)
        let alarm = try makeAlarm()
        _ = await processor.process(.create(alarm), from: .userInterface, by: .user)

        let task = Task {
            await processor.process(.disable(alarm.id), from: .userInterface, by: .user)
        }
        task.cancel()
        let outcome = await task.value

        XCTAssertEqual(outcome, .uncertain)
        let stored = try await alarms.alarm(id: alarm.id)
        XCTAssertEqual(
            stored?.isEnabled, false,
            "the local disable is applied even though the system cancel was interrupted (#10)")
        let unresolved = try await outbox.unresolvedEntries()
        XCTAssertEqual(unresolved.map(\.status), [.uncertain])
    }

    private func makeProcessor(
        alarms: CoreDataAlarmRepository, outbox: CoreDataOutboxRepository,
        controller: PersistenceController
    ) -> AlarmCommandProcessor {
        AlarmCommandProcessor(
            policy: FakeAlarmPolicyEngine(), alarms: alarms,
            audit: CoreDataAuditRepository(controller), outbox: outbox,
            alarmManager: CancellationCheckingAdapter(), clock: TestClock(now: now),
            ids: DeterministicIDGenerator(seed: 27), deviceTimeZone: { .gmt })
    }

    // MARK: - Occurrence-command safe contract

    func testUnsupportedOccurrenceCommandsHaveNoSideEffects() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        let scheduledBefore = fixture.adapter.scheduledRequests.count

        // `.cancelOccurrence` is now supported (WG-085 turn-off-today); snooze / reschedule remain.
        for command: AlarmCommand in [
            .snooze(alarm.id),
            .rescheduleOccurrence(alarm.id, fireTime: now, to: now.addingTimeInterval(600)),
        ] {
            let outcome = await fixture.processor.process(command, from: .userInterface, by: .user)
            guard case .unsupported = outcome else {
                return XCTFail(
                    "\(command) must be .unsupported, not silently applied — got \(outcome)")
            }
        }

        // The alarm and system state are untouched: no cancel/snooze reached the adapter,
        // no new schedule, and nothing was left in the outbox for these commands.
        XCTAssertEqual(fixture.adapter.scheduledRequests.count, scheduledBefore)
        XCTAssertTrue(fixture.adapter.cancelledAlarmIDs.isEmpty)
        XCTAssertTrue(fixture.adapter.snoozeCalls.isEmpty)
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored?.isEnabled, true)
        // The unsupported branch only audits (a `.noOp` per command) and touches neither the
        // outbox nor the system — a dropped occurrence command is safe, never silent success.
        let unresolved = try await fixture.outbox.unresolvedEntries()
        XCTAssertTrue(unresolved.isEmpty, "an unsupported command enqueues no external work")
        let events = try await fixture.audit.events(forAlarm: alarm.id)
        XCTAssertEqual(
            events.filter { $0.outcome == .noOp }.count, 2, "each unsupported command is audited")
    }
}

/// Throws `CancellationError` from `schedule`/`cancel` when the current Task is cancelled —
/// models a real cancellation *race* (the external call interrupted mid-flight). The
/// processor must map it to `.uncertain` and leave the outbox for reconciliation (#10),
/// never assuming the operation did not happen.
///
/// The race tests are deterministic because `task.cancel()` runs before the task can
/// traverse the several async Core Data hops (save → audit → outbox enqueue / markInProgress)
/// that precede the adapter call, so the flag is always set by the time `checkCancellation()`
/// runs. That margin comes from the real async persistence layer — a refactor that moves the
/// adapter call earlier, or swaps Core Data for a synchronous fake, could narrow it, so keep
/// a real async persistence layer in these tests.
private struct CancellationCheckingAdapter: AlarmManagerAdapter {
    func authorizationState() async -> AlarmAuthorizationState { .authorized }
    func requestAuthorization() async throws -> AlarmAuthorizationState { .authorized }
    func schedule(_ request: AlarmScheduleRequest) async throws { try Task.checkCancellation() }
    func cancel(alarmID: AlarmID) async throws { try Task.checkCancellation() }
    func stopRing(alarmID: AlarmID) async throws { try Task.checkCancellation() }
    func snooze(alarmID: AlarmID, until: Date) async throws { try Task.checkCancellation() }
    func scheduledAlarms() async throws -> [ScheduledAlarmSnapshot] { [] }
}
