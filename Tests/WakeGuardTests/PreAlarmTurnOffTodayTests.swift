import XCTest

@testable import WakeGuard

/// WG-085: the turn-off-today action (occurrence-level cancel). Verifies the scheduling engine skips a
/// turned-off occurrence while keeping the next recurrence correct, and that the processor's
/// `.cancelOccurrence` handler affects **only the occurrence** (the alarm stays enabled, its schedule
/// unchanged), requires **confirmation for a critical alarm** (#6), and is stale-safe.
final class PreAlarmTurnOffTodayTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 85)
    private let engine = AlarmSchedulingEngine()

    private func iso(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func makeAlarm(criticality: Criticality = .standard) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule, criticality: criticality,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    private func makeOneTimeAlarm() throws -> Alarm {
        let schedule = ScheduleRule.oneTime(
            OneTimeSchedule(
                date: try CalendarDate(year: 2026, month: 8, day: 17),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "once", schedule: schedule, createdAt: epoch,
            updatedAt: epoch, revision: 0)
    }

    // MARK: - Engine: skipping an occurrence keeps the next recurrence correct

    func testSkippingTodayReturnsNextRecurrence() throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let alarm = try makeAlarm()
        let today = try XCTUnwrap(
            engine.nextOccurrence(for: alarm, after: now, deviceTimeZone: .gmt))
        XCTAssertEqual(today, try iso("2026-08-17T07:00:00Z"), "the un-skipped next occurrence")
        var skipped = alarm
        skipped.skippedOccurrences = [today]
        XCTAssertEqual(
            engine.nextOccurrence(for: skipped, after: now, deviceTimeZone: .gmt),
            try iso("2026-08-18T07:00:00Z"), "skips today, returns the next recurrence")
    }

    func testMultipleConsecutiveSkipsAdvancePastAll() throws {
        let now = try iso("2026-08-17T06:00:00Z")
        var skipped = try makeAlarm()
        skipped.skippedOccurrences = [
            try iso("2026-08-17T07:00:00Z"), try iso("2026-08-18T07:00:00Z"),
        ]
        XCTAssertEqual(
            engine.nextOccurrence(for: skipped, after: now, deviceTimeZone: .gmt),
            try iso("2026-08-19T07:00:00Z"), "skips both days, returns the third")
    }

    func testOneTimeAlarmWithSkippedOccurrenceHasNoNext() throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let oneTime = try makeOneTimeAlarm()
        let occ = try XCTUnwrap(
            engine.nextOccurrence(for: oneTime, after: now, deviceTimeZone: .gmt))
        var skipped = oneTime
        skipped.skippedOccurrences = [occ]
        XCTAssertNil(
            engine.nextOccurrence(for: skipped, after: now, deviceTimeZone: .gmt),
            "a one-time alarm's only occurrence, skipped, has no next")
    }

    // MARK: - Processor: cancel today's occurrence only

    private struct Fixture {
        let processor: AlarmCommandProcessor
        let alarms: CoreDataAlarmRepository
        let adapter: FakeAlarmManagerAdapter
    }

    private func reload(_ id: AlarmID, in fixture: Fixture) async throws -> Alarm {
        let loaded = try await fixture.alarms.alarm(id: id)
        return try XCTUnwrap(loaded)
    }

    private func makeFixture(now: Date) throws -> Fixture {
        let controller = try PersistenceController(inMemory: true)
        let adapter = FakeAlarmManagerAdapter()
        let alarms = CoreDataAlarmRepository(controller)
        let clock = TestClock(now: now)
        let processor = AlarmCommandProcessor(
            policy: DefaultAlarmPolicyEngine(
                alarms: alarms, clock: clock, deviceTimeZone: { .gmt }),
            alarms: alarms, audit: CoreDataAuditRepository(controller),
            outbox: CoreDataOutboxRepository(controller), alarmManager: adapter, clock: clock,
            ids: DeterministicIDGenerator(seed: 27), deviceTimeZone: { .gmt })
        return Fixture(processor: processor, alarms: alarms, adapter: adapter)
    }

    func testTurnOffTodayAffectsOnlyTheOccurrence() async throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let fixture = try makeFixture(now: now)
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        let today = try XCTUnwrap(
            engine.nextOccurrence(for: alarm, after: now, deviceTimeZone: .gmt))

        let outcome = await fixture.processor.process(
            .cancelOccurrence(alarm.id, fireTime: today), from: .notificationAction, by: .user)

        XCTAssertEqual(outcome, .applied)
        let reloaded = try await reload(alarm.id, in: fixture)
        XCTAssertTrue(reloaded.skippedOccurrences.contains(today), "today's occurrence is skipped")
        XCTAssertTrue(
            reloaded.isEnabled, "the alarm stays enabled — only the occurrence is affected")
        XCTAssertEqual(reloaded.schedule, alarm.schedule, "the recurrence rule is unchanged")
        XCTAssertGreaterThan(reloaded.revision, alarm.revision)
        XCTAssertEqual(
            fixture.adapter.scheduledRequests.last?.fireTime, try iso("2026-08-18T07:00:00Z"),
            "AlarmKit is re-armed for the next recurrence, not today")
    }

    func testNextRecurrenceRemainsCorrectAfterTurnOff() async throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let fixture = try makeFixture(now: now)
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        let today = try XCTUnwrap(
            engine.nextOccurrence(for: alarm, after: now, deviceTimeZone: .gmt))
        _ = await fixture.processor.process(
            .cancelOccurrence(alarm.id, fireTime: today), from: .notificationAction, by: .user)

        let reloaded = try await reload(alarm.id, in: fixture)
        XCTAssertEqual(
            engine.nextOccurrence(for: reloaded, after: now, deviceTimeZone: .gmt),
            try iso("2026-08-18T07:00:00Z"), "next recurrence is tomorrow, from the reloaded state")
    }

    func testCriticalTurnOffTodayRequiresConfirmation() async throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let fixture = try makeFixture(now: now)
        let critical = try makeAlarm(criticality: .critical)
        _ = await fixture.processor.process(.create(critical), from: .userInterface, by: .user)
        let today = try XCTUnwrap(
            engine.nextOccurrence(for: critical, after: now, deviceTimeZone: .gmt))

        let unconfirmed = await fixture.processor.process(
            .cancelOccurrence(critical.id, fireTime: today), from: .notificationAction, by: .user,
            userConfirmed: false)
        guard case .needsConfirmation = unconfirmed else {
            return XCTFail("a critical alarm's turn-off-today must require confirmation (#6)")
        }
        let unchanged = try await reload(critical.id, in: fixture)
        XCTAssertTrue(unchanged.skippedOccurrences.isEmpty, "no mutation without confirmation")

        let confirmed = await fixture.processor.process(
            .cancelOccurrence(critical.id, fireTime: today), from: .notificationAction, by: .user,
            userConfirmed: true)
        XCTAssertEqual(confirmed, .applied)
        let skipped = try await reload(critical.id, in: fixture)
        XCTAssertTrue(skipped.skippedOccurrences.contains(today), "confirmed turn-off skips it")
    }

    func testStalePastOccurrenceIsSafeNoOp() async throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let fixture = try makeFixture(now: now)
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)

        let outcome = await fixture.processor.process(
            .cancelOccurrence(alarm.id, fireTime: try iso("2026-08-16T07:00:00Z")),
            from: .notificationAction, by: .user)

        XCTAssertEqual(outcome, .noOp, "cancelling an already-passed occurrence is a safe no-op")
        let reloaded = try await reload(alarm.id, in: fixture)
        XCTAssertTrue(reloaded.skippedOccurrences.isEmpty, "no skip added for a past occurrence")
        XCTAssertEqual(reloaded.revision, alarm.revision, "no mutation")
    }

    func testTurnOffTodayForMissingAlarmIsNoOp() async throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let fixture = try makeFixture(now: now)
        let outcome = await fixture.processor.process(
            .cancelOccurrence(AlarmID(ids.next()), fireTime: try iso("2026-08-17T07:00:00Z")),
            from: .notificationAction, by: .user)
        XCTAssertEqual(outcome, .noOp)
    }

    func testReconciliationHonorsSkippedOccurrence() throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let today = try iso("2026-08-17T07:00:00Z")
        var alarm = try makeAlarm()
        alarm.skippedOccurrences = [today]
        // The system authority still holds today's occurrence (a stale schedule).
        let systemHoldingToday = ScheduledAlarmSnapshot(
            alarmID: alarm.id, fireTime: today, isCritical: false)

        let repairs = AlarmReconciler().plan(
            desired: [alarm], system: [systemHoldingToday], now: now, deviceTimeZone: .gmt)

        XCTAssertEqual(
            repairs,
            [
                .schedule(
                    AlarmScheduleRequest(
                        alarmID: alarm.id, fireTime: try iso("2026-08-18T07:00:00Z"),
                        title: alarm.label, isCritical: false))
            ], "reconciliation re-arms tomorrow, never resurrects the turned-off occurrence")
    }

    func testTurnOffTodayPersistsSkipEvenIfRescheduleFails() async throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let fixture = try makeFixture(now: now)
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        let today = try XCTUnwrap(
            engine.nextOccurrence(for: alarm, after: now, deviceTimeZone: .gmt))
        fixture.adapter.inject(.failed(reason: "system busy"), on: .schedule)

        let outcome = await fixture.processor.process(
            .cancelOccurrence(alarm.id, fireTime: today), from: .notificationAction, by: .user)

        guard case .failed = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        let reloaded = try await reload(alarm.id, in: fixture)
        XCTAssertTrue(
            reloaded.skippedOccurrences.contains(today),
            "the local skip is durable even if the reschedule failed (#10); reconciliation re-arms")
    }

    func testDoubleTurnOffSameOccurrenceIsIdempotent() async throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let fixture = try makeFixture(now: now)
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        let today = try XCTUnwrap(
            engine.nextOccurrence(for: alarm, after: now, deviceTimeZone: .gmt))

        for _ in 0..<2 {
            _ = await fixture.processor.process(
                .cancelOccurrence(alarm.id, fireTime: today), from: .notificationAction, by: .user)
        }

        let reloaded = try await reload(alarm.id, in: fixture)
        XCTAssertEqual(
            reloaded.skippedOccurrences.count, 1, "the same occurrence is skipped exactly once")
    }

    func testOneTimeTurnOffTodayLeavesNoNextOccurrenceAndCancels() async throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let fixture = try makeFixture(now: now)
        let oneTime = try makeOneTimeAlarm()
        _ = await fixture.processor.process(.create(oneTime), from: .userInterface, by: .user)
        let today = try XCTUnwrap(
            engine.nextOccurrence(for: oneTime, after: now, deviceTimeZone: .gmt))

        _ = await fixture.processor.process(
            .cancelOccurrence(oneTime.id, fireTime: today), from: .notificationAction, by: .user)

        let reloaded = try await reload(oneTime.id, in: fixture)
        XCTAssertNil(
            engine.nextOccurrence(for: reloaded, after: now, deviceTimeZone: .gmt),
            "the only occurrence is skipped → no next")
        XCTAssertEqual(
            fixture.adapter.cancelledAlarmIDs.last, oneTime.id,
            "AlarmKit is cancelled when no occurrence remains")
    }
}
