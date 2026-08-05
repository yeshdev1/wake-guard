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
}

/// An alarm repository whose reads always throw — proves reconciliation fails safe when
/// the desired state cannot be read (#10), rather than treating it as "no alarms."
private struct FailingAlarmRepository: AlarmRepository {
    func save(_ alarm: Alarm) async throws { throw AlarmRepositoryError.storageUnavailable }
    func alarm(id: AlarmID) async throws -> Alarm? { throw AlarmRepositoryError.storageUnavailable }
    func allAlarms() async throws -> [Alarm] { throw AlarmRepositoryError.storageUnavailable }
    func deleteAlarm(id: AlarmID) async throws { throw AlarmRepositoryError.storageUnavailable }
}
