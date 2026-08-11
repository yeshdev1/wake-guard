import XCTest

@testable import WakeGuard

/// WG-029: the reconciliation driver on `AlarmCommandProcessor`. Verifies it schedules a
/// missing alarm, cancels an extra system alarm, is idempotent on re-run, audits each
/// repair as `.systemReconciliation` (#46/#50), continues after a single repair fails,
/// and — critically — repairs NOTHING when ground truth or the desired state cannot be
/// read (#10: never repair blind, never cancel everything on a failed desired read).
final class AlarmReconciliationTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 129)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Fixture {
        let processor: AlarmCommandProcessor
        let alarms: CoreDataAlarmRepository
        let audit: CoreDataAuditRepository
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
        return Fixture(processor: processor, alarms: alarms, audit: audit, adapter: adapter)
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

    private func snapshot(_ id: AlarmID) -> ScheduledAlarmSnapshot {
        ScheduledAlarmSnapshot(
            alarmID: id, fireTime: now.addingTimeInterval(3600), isCritical: false)
    }

    func testReconcileSchedulesMissingAlarmAndAuditsAsReconciliation() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        try await fixture.alarms.save(alarm)

        let summary = await fixture.processor.reconcile()

        XCTAssertEqual(summary, ReconciliationSummary(scheduled: 1))
        let request = try XCTUnwrap(fixture.adapter.scheduledRequests.first)
        XCTAssertEqual(request.alarmID, alarm.id)
        XCTAssertGreaterThan(request.fireTime, now)
        let events = try await fixture.audit.events(forAlarm: alarm.id)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.actor, .systemReconciliation)
        XCTAssertEqual(event.source, .reconciliation)
        XCTAssertEqual(event.outcome, .succeeded)
    }

    func testReconcileCancelsExtraSystemAlarm() async throws {
        let fixture = try makeFixture()
        let strayID = AlarmID(ids.next())
        fixture.adapter.setScheduled([snapshot(strayID)])

        let summary = await fixture.processor.reconcile()

        XCTAssertEqual(summary, ReconciliationSummary(cancelled: 1))
        XCTAssertEqual(fixture.adapter.cancelledAlarmIDs, [strayID])
        let event = try await fixture.audit.events(forAlarm: strayID).first
        XCTAssertEqual(event?.actor, .systemReconciliation)
    }

    func testReconcileIsIdempotent() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        try await fixture.alarms.save(alarm)

        _ = await fixture.processor.reconcile()  // first pass schedules it
        let second = await fixture.processor.reconcile()  // system now matches desired

        XCTAssertEqual(second, ReconciliationSummary(), "a matching system needs no repair")
        XCTAssertEqual(
            fixture.adapter.scheduledRequests.count, 1,
            "no duplicate schedule on the second pass")
    }

    func testReconcileSkipsWhenGroundTruthUnreadable() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        try await fixture.alarms.save(alarm)
        fixture.adapter.inject(.unavailable, on: .query)

        let summary = await fixture.processor.reconcile()

        XCTAssertEqual(summary, ReconciliationSummary(skipped: true))
        XCTAssertTrue(
            fixture.adapter.scheduledRequests.isEmpty, "never repair against an unknown system")
        XCTAssertTrue(fixture.adapter.cancelledAlarmIDs.isEmpty)
    }

    func testReconcileSkipsWhenDesiredStateUnreadable() async throws {
        // #10: a *failed* desired read must not be treated as "no alarms" — otherwise
        // reconciliation would cancel every system alarm. The system holds an alarm, the
        // local read throws, and nothing may be cancelled.
        let controller = try PersistenceController(inMemory: true)
        let audit = CoreDataAuditRepository(controller)
        let outbox = CoreDataOutboxRepository(controller)
        let adapter = FakeAlarmManagerAdapter()
        adapter.setScheduled([snapshot(AlarmID(ids.next()))])
        let processor = AlarmCommandProcessor(
            policy: FakeAlarmPolicyEngine(), alarms: FailingAlarmRepository(), audit: audit,
            outbox: outbox, alarmManager: adapter, clock: TestClock(now: now),
            ids: DeterministicIDGenerator(seed: 27), deviceTimeZone: { .gmt })

        let summary = await processor.reconcile()

        XCTAssertEqual(summary, ReconciliationSummary(skipped: true))
        XCTAssertTrue(
            adapter.cancelledAlarmIDs.isEmpty,
            "a failed desired read must never cancel system alarms (#10)")
    }

    func testReconcileContinuesAfterOneRepairFails() async throws {
        // One missing alarm (→ schedule, injected to fail) and one extra system alarm
        // (→ cancel, succeeds): the failed schedule must not abort the cancel.
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        try await fixture.alarms.save(alarm)
        let strayID = AlarmID(ids.next())
        fixture.adapter.setScheduled([snapshot(strayID)])
        fixture.adapter.inject(.failed(reason: "boom"), on: .schedule)

        let summary = await fixture.processor.reconcile()

        XCTAssertEqual(summary, ReconciliationSummary(scheduled: 0, cancelled: 1, failed: 1))
        XCTAssertEqual(fixture.adapter.cancelledAlarmIDs, [strayID], "the cancel still ran")
        let event = try await fixture.audit.events(forAlarm: alarm.id).first
        XCTAssertEqual(event?.outcome, .failed)
        XCTAssertEqual(event?.userVisibleReason, "The alarm could not be updated in the system.")
    }

    func testReconcileCountsUncertainRepairSeparately() async throws {
        // An interrupted (uncertain) repair is NOT a hard failure: it is counted apart, the
        // local alarm is preserved, and the next pass re-checks ground truth (#10).
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        try await fixture.alarms.save(alarm)
        fixture.adapter.inject(.uncertain, on: .schedule)

        let summary = await fixture.processor.reconcile()

        XCTAssertEqual(summary, ReconciliationSummary(uncertain: 1))
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(stored, alarm, "the local alarm is preserved after an uncertain repair")
    }

    func testStaleCancelIsSkippedWhenAConcurrentEnableRestoredTheAlarm() async throws {
        // WG-244 lost-update guard: the plan is computed from a snapshot where the alarm is disabled
        // (so it plans a `cancel`), but by apply time a concurrent `enable`/`create` has restored it.
        // The stale cancel must be DROPPED — applying it would silently drop a wanted ring (#10).
        let alarm = try makeAlarm()  // enabled weekly 07:00 — has a future occurrence
        let repo = InterleavingAlarmRepository(alarm, planTimeEnabled: false)
        let controller = try PersistenceController(inMemory: true)
        let adapter = FakeAlarmManagerAdapter()
        adapter.setScheduled([snapshot(alarm.id)])  // system still holds it → planned as "extra"
        let processor = AlarmCommandProcessor(
            policy: FakeAlarmPolicyEngine(), alarms: repo,
            audit: CoreDataAuditRepository(controller),
            outbox: CoreDataOutboxRepository(controller),
            alarmManager: adapter, clock: TestClock(now: now),
            ids: DeterministicIDGenerator(seed: 27), deviceTimeZone: { .gmt })

        let summary = await processor.reconcile()

        XCTAssertEqual(summary, ReconciliationSummary(stale: 1))
        XCTAssertTrue(
            adapter.cancelledAlarmIDs.isEmpty,
            "a cancel invalidated by a concurrent enable must never drop the alarm (#10, WG-244)")
        XCTAssertEqual(
            adapter.currentlyScheduled.map(\.alarmID), [alarm.id],
            "the wanted alarm stays scheduled")
    }

    func testStaleScheduleIsSkippedWhenAConcurrentDisableRemovedTheAlarm() async throws {
        // The mirror case: the plan is computed while the alarm is enabled (so it plans a `schedule`),
        // but by apply time a concurrent `disable`/`delete` removed the desired schedule. The stale
        // schedule must be DROPPED — otherwise reconciliation resurrects an alarm the user just cleared.
        let alarm = try makeAlarm()
        let repo = InterleavingAlarmRepository(alarm, planTimeEnabled: true)
        let controller = try PersistenceController(inMemory: true)
        // System empty → the alarm is "missing" → the planner emits a schedule.
        let adapter = FakeAlarmManagerAdapter()
        let processor = AlarmCommandProcessor(
            policy: FakeAlarmPolicyEngine(), alarms: repo,
            audit: CoreDataAuditRepository(controller),
            outbox: CoreDataOutboxRepository(controller),
            alarmManager: adapter, clock: TestClock(now: now),
            ids: DeterministicIDGenerator(seed: 27), deviceTimeZone: { .gmt })

        let summary = await processor.reconcile()

        XCTAssertEqual(summary, ReconciliationSummary(stale: 1))
        XCTAssertTrue(
            adapter.scheduledRequests.isEmpty,
            "a schedule invalidated by a concurrent disable must not resurrect the alarm")
    }

    func testCancelRepairIsDeferredWhenTheRevalidationReadFails() async throws {
        // WG-251: if the apply-time re-validation read throws (a transient store failure), a planned cancel
        // must be DEFERRED (fail closed, #10) — not applied on unknown state. The rest of the processor
        // fails closed; the WG-244 re-validation must too. The system alarm is left for the next pass.
        let alarm = try makeAlarm()
        let repo = RevalidationReadFailsAlarmRepository(alarm)
        let controller = try PersistenceController(inMemory: true)
        let adapter = FakeAlarmManagerAdapter()
        adapter.setScheduled([snapshot(alarm.id)])  // system holds it → planned as "extra" → cancel
        let processor = AlarmCommandProcessor(
            policy: FakeAlarmPolicyEngine(), alarms: repo,
            audit: CoreDataAuditRepository(controller),
            outbox: CoreDataOutboxRepository(controller),
            alarmManager: adapter, clock: TestClock(now: now),
            ids: DeterministicIDGenerator(seed: 27), deviceTimeZone: { .gmt })

        let summary = await processor.reconcile()

        XCTAssertEqual(summary, ReconciliationSummary(stale: 1))
        XCTAssertTrue(
            adapter.cancelledAlarmIDs.isEmpty,
            "a cancel must be deferred when the re-validation read fails, not applied on unknown state"
        )
        XCTAssertEqual(adapter.currentlyScheduled.map(\.alarmID), [alarm.id])
    }
}

/// An alarm repository whose reads always throw — proves reconciliation fails safe when
/// the desired state cannot be read (#10), rather than treating it as "no alarms."
private struct FailingAlarmRepository: AlarmRepository {
    func save(_ alarm: Alarm) async throws { throw AlarmRepositoryError.storageUnavailable }
    func alarm(id: AlarmID) async throws -> Alarm? { throw AlarmRepositoryError.storageUnavailable }
    func allAlarms() async throws -> [Alarm] { throw AlarmRepositoryError.storageUnavailable }
    func deleteAlarm(id: AlarmID) async throws { throw AlarmRepositoryError.storageUnavailable }
}

/// Models a concurrent enable/disable landing *between* the reconcile plan read (`allAlarms`) and the
/// per-repair re-validation read (`alarm(id:)`), WG-244. `allAlarms()` reports the alarm with its
/// plan-time enable state once (flipping an internal marker); every later `alarm(id:)` reports the
/// *opposite* state — exactly what a concurrent command would have committed by apply time. This lets
/// a single-threaded test deterministically exercise the lost-update window without a real race.
private final class InterleavingAlarmRepository: AlarmRepository {
    private let stored: Alarm
    private let planTimeEnabled: Bool
    private let planned = Synchronized(false)

    init(_ alarm: Alarm, planTimeEnabled: Bool) {
        stored = alarm
        self.planTimeEnabled = planTimeEnabled
    }

    func allAlarms() async throws -> [Alarm] {
        planned.mutate { $0 = true }
        return [withEnabled(planTimeEnabled)]
    }

    func alarm(id: AlarmID) async throws -> Alarm? {
        guard id == stored.id else { return nil }
        return planned.get() ? withEnabled(!planTimeEnabled) : withEnabled(planTimeEnabled)
    }

    func save(_ alarm: Alarm) async throws {}
    func deleteAlarm(id: AlarmID) async throws {}

    private func withEnabled(_ isEnabled: Bool) -> Alarm {
        var copy = stored
        copy.isEnabled = isEnabled
        return copy
    }
}

/// `allAlarms()` reports the alarm disabled (so the planner emits a cancel), then `alarm(id:)` — the
/// apply-time re-validation read — throws, modeling a transient store failure during reconcile (WG-251).
/// Proves the re-validation defers the repair on a read failure instead of cancelling on unknown state.
private final class RevalidationReadFailsAlarmRepository: AlarmRepository {
    private let stored: Alarm

    init(_ alarm: Alarm) { stored = alarm }

    func allAlarms() async throws -> [Alarm] {
        var disabled = stored
        disabled.isEnabled = false
        return [disabled]
    }

    func alarm(id: AlarmID) async throws -> Alarm? { throw AlarmRepositoryError.storageUnavailable }
    func save(_ alarm: Alarm) async throws {}
    func deleteAlarm(id: AlarmID) async throws {}
}
