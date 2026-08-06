import XCTest

@testable import WakeGuard

/// WG-027: the transactional command processor. Verifies every command is authorized
/// (a rejection mutates nothing), that create/enable schedule + disable cancels with
/// the outbox and audit written around the external call, and that uncertain/failed
/// external outcomes preserve local state (#10) — uncertain leaving the outbox entry
/// for reconciliation.
final class AlarmCommandProcessorTests: XCTestCase {

    private let alarmIDs = DeterministicIDGenerator(seed: 99)

    private struct Fixture {
        let processor: AlarmCommandProcessor
        let policy: FakeAlarmPolicyEngine
        let alarms: CoreDataAlarmRepository
        let audit: CoreDataAuditRepository
        let outbox: CoreDataOutboxRepository
        let adapter: FakeAlarmManagerAdapter
        let clock: TestClock
    }

    private func makeFixture(decision: PolicyDecision = .authorized) throws -> Fixture {
        let controller = try PersistenceController(inMemory: true)
        let policy = FakeAlarmPolicyEngine(decision: decision)
        let alarms = CoreDataAlarmRepository(controller)
        let audit = CoreDataAuditRepository(controller)
        let outbox = CoreDataOutboxRepository(controller)
        let adapter = FakeAlarmManagerAdapter()
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))
        let processor = AlarmCommandProcessor(
            policy: policy, alarms: alarms, audit: audit, outbox: outbox, alarmManager: adapter,
            clock: clock, ids: DeterministicIDGenerator(seed: 27), deviceTimeZone: { .gmt })
        return Fixture(
            processor: processor, policy: policy, alarms: alarms, audit: audit, outbox: outbox,
            adapter: adapter, clock: clock)
    }

    private func makeAlarm(enabled: Bool = true) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(alarmIDs.next()), label: "wake", isEnabled: enabled, schedule: schedule,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    func testRejectedCommandMutatesNothing() async throws {
        let fixture = try makeFixture(decision: .rejected(reason: "not allowed"))
        let alarm = try makeAlarm()
        let outcome = await fixture.processor.process(
            .create(alarm), from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .rejected(reason: "not allowed"))
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertNil(stored, "a rejected command must not save the alarm")
        XCTAssertTrue(fixture.adapter.scheduledRequests.isEmpty, "no external call on rejection")
        let events = try await fixture.audit.events(forAlarm: alarm.id)
        XCTAssertEqual(events.map(\.outcome), [.rejected])
    }

    func testCreateSchedulesAndWritesOutboxAndAudit() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        let outcome = await fixture.processor.process(
            .create(alarm), from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .applied)
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored, alarm)

        let request = try XCTUnwrap(fixture.adapter.scheduledRequests.first)
        XCTAssertEqual(fixture.adapter.scheduledRequests.count, 1)
        XCTAssertEqual(request.alarmID, alarm.id)
        XCTAssertGreaterThan(request.fireTime, fixture.clock.now)

        let unresolved = try await fixture.outbox.unresolvedEntries()
        XCTAssertTrue(unresolved.isEmpty, "the scheduled op is applied, not left pending")

        let events = try await fixture.audit.events(forAlarm: alarm.id)
        XCTAssertEqual(events.map(\.outcome), [.succeeded])
        XCTAssertNil(events.first?.oldStateHash, "create has no prior state")
        XCTAssertNotNil(events.first?.newStateHash)
    }

    func testDisableCancelsAndBumpsRevision() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)

        let outcome = await fixture.processor.process(
            .disable(alarm.id), from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(fixture.adapter.cancelledAlarmIDs, [alarm.id])
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored?.isEnabled, false)
        XCTAssertEqual(stored?.revision, 1)
    }

    func testEnableSchedulesAPreviouslyDisabledAlarm() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm(enabled: false)
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        XCTAssertTrue(
            fixture.adapter.scheduledRequests.isEmpty, "a disabled alarm is not scheduled")

        let outcome = await fixture.processor.process(
            .enable(alarm.id), from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(fixture.adapter.scheduledRequests.count, 1)
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored?.isEnabled, true)
        XCTAssertEqual(stored?.revision, 1)
    }

    func testUncertainOutcomeLeavesOutboxForReconciliation() async throws {
        let fixture = try makeFixture()
        fixture.adapter.inject(.uncertain, on: .schedule)
        let alarm = try makeAlarm()

        let outcome = await fixture.processor.process(
            .create(alarm), from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .uncertain)
        // #10: the local state is applied even though the external outcome is unknown.
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored, alarm)
        // The outbox entry is left uncertain for reconciliation (WG-029).
        let unresolved = try await fixture.outbox.unresolvedEntries()
        XCTAssertEqual(unresolved.count, 1)
        XCTAssertEqual(unresolved.first?.status, .uncertain)
    }

    func testFailedExternalCallPreservesLocalState() async throws {
        let fixture = try makeFixture()
        fixture.adapter.inject(.failed(reason: "busy"), on: .schedule)
        let alarm = try makeAlarm()

        let outcome = await fixture.processor.process(
            .create(alarm), from: .userInterface, by: .user)

        guard case .failed = outcome else {
            return XCTFail("expected .failed, got \(outcome)")
        }
        // #10: a failed external call must not drop the locally-saved alarm.
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored, alarm)
    }

    func testSnoozeIsUnsupportedNotSilentSuccess() async throws {
        // An occurrence-level command the processor does not yet apply is authorized
        // (#3) and audited (#46), and returns `.unsupported` — never a success-like
        // `.noOp` a caller could mistake for a completed snooze.
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        let outcome = await fixture.processor.process(
            .snooze(alarm.id), from: .userInterface, by: .user)

        guard case .unsupported = outcome else {
            return XCTFail("snooze must not silently succeed, got \(outcome)")
        }
        XCTAssertEqual(fixture.policy.seenCommands.count, 1)
        let events = try await fixture.audit.events(forAlarm: alarm.id)
        XCTAssertEqual(events.map(\.outcome), [.noOp])
    }

    func testUpdateReschedulesWithBumpedRevision() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)

        var updated = alarm
        updated.label = "renamed"
        updated.revision = 1
        updated.updatedAt = fixture.clock.now
        let outcome = await fixture.processor.process(
            .update(updated), from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .applied)
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored?.label, "renamed")
        XCTAssertEqual(stored?.revision, 1)
        XCTAssertEqual(fixture.adapter.scheduledRequests.count, 2, "rescheduled after the edit")
        XCTAssertEqual(fixture.adapter.scheduledRequests.last?.title, "renamed")
    }

    func testStaleUpdateIsRejectedAsConcurrentEdit() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)

        // An update carrying the same (stale) revision must not overwrite.
        var stale = alarm
        stale.label = "renamed"
        let outcome = await fixture.processor.process(
            .update(stale), from: .userInterface, by: .user)

        guard case .failed(let reason) = outcome else {
            return XCTFail("expected .failed, got \(outcome)")
        }
        XCTAssertTrue(
            reason.contains("changed elsewhere"),
            "a concurrent-edit conflict is distinct from a generic storage failure")
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored?.label, "wake", "the stale update did not overwrite")
    }

    func testCancelledExternalCallIsUncertain() async throws {
        // A cancelled adapter call may already have applied — the processor must treat
        // it as uncertain, never assume it did not happen (#10).
        let controller = try PersistenceController(inMemory: true)
        let processor = AlarmCommandProcessor(
            policy: FakeAlarmPolicyEngine(), alarms: CoreDataAlarmRepository(controller),
            audit: CoreDataAuditRepository(controller),
            outbox: CoreDataOutboxRepository(controller),
            alarmManager: CancellingAdapter(),
            clock: TestClock(now: Date(timeIntervalSince1970: 1_000_000)),
            ids: DeterministicIDGenerator(seed: 27), deviceTimeZone: { .gmt })
        let alarm = try makeAlarm()

        let outcome = await processor.process(.create(alarm), from: .userInterface, by: .user)
        XCTAssertEqual(outcome, .uncertain)
    }

    func testDeleteRemovesLocalAndCancelsSystem() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)

        let outcome = await fixture.processor.process(
            .delete(alarm.id), from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .applied)
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertNil(stored, "the local alarm is deleted (source of truth first, #10)")
        XCTAssertEqual(
            fixture.adapter.cancelledAlarmIDs, [alarm.id], "the system alarm is cancelled")
        let events = try await fixture.audit.events(forAlarm: alarm.id)
        XCTAssertEqual(events.last?.outcome, .succeeded)
        XCTAssertNil(events.last?.newStateHash, "a delete has no new state")
    }

    /// A definite system-cancel failure must NOT downgrade the delete: the local record
    /// (source of truth, #10) is already gone, so the alarm is deleted and the outcome stays
    /// `.applied`. The stranded system alarm is the safe direction (a spurious ring, never a
    /// missed one) and is reaped by reconciliation (WG-029) — criterion 3, a coherent safe
    /// state on failure (no vanished-row-plus-scary-error incoherence).
    func testDeleteWithFailedSystemCancelStillReportsDeleted() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        fixture.adapter.inject(.failed(reason: "busy"), on: .cancel)

        let outcome = await fixture.processor.process(
            .delete(alarm.id), from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .applied, "a failed system cancel doesn't undo a done local delete")
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertNil(stored, "the local alarm is gone regardless of the system cancel result")
        let events = try await fixture.audit.events(forAlarm: alarm.id)
        XCTAssertEqual(events.last?.outcome, .succeeded, "the delete is audited as succeeded")
    }

    func testDeletingUnknownAlarmIsNoOp() async throws {
        let fixture = try makeFixture()
        let outcome = await fixture.processor.process(
            .delete(AlarmID(alarmIDs.next())), from: .userInterface, by: .user)
        XCTAssertEqual(outcome, .noOp, "deleting a non-existent alarm is a safe no-op")
    }

    /// Throws `CancellationError` on `schedule` — a non-`AlarmManagerError` throw, to
    /// exercise the processor's defensive cancellation-to-uncertain mapping.
    private struct CancellingAdapter: AlarmManagerAdapter {
        func authorizationState() async -> AlarmAuthorizationState { .authorized }
        func requestAuthorization() async throws -> AlarmAuthorizationState { .authorized }
        func schedule(_ request: AlarmScheduleRequest) async throws { throw CancellationError() }
        func cancel(alarmID: AlarmID) async throws {}
        func snooze(alarmID: AlarmID, until: Date) async throws {}
        func scheduledAlarms() async throws -> [ScheduledAlarmSnapshot] { [] }
    }
}
