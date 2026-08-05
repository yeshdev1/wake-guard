import XCTest

@testable import WakeGuard

/// WG-029: the pure reconciliation planner. Verifies it detects the three divergences —
/// missing, extra, and divergent (fire time or criticality) — that a matching system
/// produces no repairs (idempotent), and that a disabled alarm is not desired (so its
/// system alarm is extra).
final class AlarmReconcilerTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 29)
    private let reconciler = AlarmReconciler()
    private let engine = AlarmSchedulingEngine()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeAlarm(enabled: Bool = true, criticality: Criticality = .standard) throws
        -> Alarm
    {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", isEnabled: enabled, schedule: schedule,
            criticality: criticality, createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    private func nextOccurrence(_ alarm: Alarm) throws -> Date {
        try XCTUnwrap(engine.nextOccurrence(for: alarm, after: now, deviceTimeZone: .gmt))
    }

    func testMissingAlarmIsScheduled() throws {
        let alarm = try makeAlarm()
        let expected = AlarmScheduleRequest(
            alarmID: alarm.id, fireTime: try nextOccurrence(alarm), title: "wake",
            isCritical: false)
        let plan = reconciler.plan(desired: [alarm], system: [], now: now, deviceTimeZone: .gmt)
        XCTAssertEqual(plan, [.schedule(expected)])
    }

    func testMatchingSystemProducesNoRepairs() throws {
        let alarm = try makeAlarm()
        let held = ScheduledAlarmSnapshot(
            alarmID: alarm.id, fireTime: try nextOccurrence(alarm), isCritical: false)
        let plan = reconciler.plan(
            desired: [alarm], system: [held], now: now, deviceTimeZone: .gmt)
        XCTAssertTrue(plan.isEmpty, "a system that matches desired needs no repair (idempotent)")
    }

    func testExtraSystemAlarmIsCancelled() throws {
        let strayID = AlarmID(ids.next())
        let stray = ScheduledAlarmSnapshot(
            alarmID: strayID, fireTime: now.addingTimeInterval(3600), isCritical: false)
        let plan = reconciler.plan(desired: [], system: [stray], now: now, deviceTimeZone: .gmt)
        XCTAssertEqual(plan, [.cancel(strayID)])
    }

    func testDivergentFireTimeIsRescheduled() throws {
        let alarm = try makeAlarm()
        let correct = try nextOccurrence(alarm)
        let drifted = ScheduledAlarmSnapshot(
            alarmID: alarm.id, fireTime: correct.addingTimeInterval(3600), isCritical: false)
        let expected = AlarmScheduleRequest(
            alarmID: alarm.id, fireTime: correct, title: "wake", isCritical: false)
        let plan = reconciler.plan(
            desired: [alarm], system: [drifted], now: now, deviceTimeZone: .gmt)
        XCTAssertEqual(
            plan, [.schedule(expected)],
            "a drifted fire time must be re-scheduled to the correct occurrence")
    }

    func testDivergentCriticalityIsRescheduled() throws {
        let alarm = try makeAlarm(criticality: .critical)
        let correct = try nextOccurrence(alarm)
        // The system holds it at the right time but as NON-critical — a silent downgrade.
        let downgraded = ScheduledAlarmSnapshot(
            alarmID: alarm.id, fireTime: correct, isCritical: false)
        let expected = AlarmScheduleRequest(
            alarmID: alarm.id, fireTime: correct, title: "wake", isCritical: true)
        let plan = reconciler.plan(
            desired: [alarm], system: [downgraded], now: now, deviceTimeZone: .gmt)
        XCTAssertEqual(
            plan, [.schedule(expected)],
            "a critical alarm silently downgraded in the system must be re-scheduled critical")
    }

    func testDisabledAlarmIsExtraAndCancelled() throws {
        let alarm = try makeAlarm(enabled: false)
        let held = ScheduledAlarmSnapshot(
            alarmID: alarm.id, fireTime: now.addingTimeInterval(3600), isCritical: false)
        let plan = reconciler.plan(
            desired: [alarm], system: [held], now: now, deviceTimeZone: .gmt)
        XCTAssertEqual(
            plan, [.cancel(alarm.id)],
            "a disabled alarm is not desired, so its system alarm is extra")
    }

    func testMultipleRepairsAreSortedById() throws {
        // Two missing (schedule) + one extra (cancel): the plan is ordered by target id,
        // so reconciliation applies (and audits) repairs deterministically.
        let first = try makeAlarm()
        let second = try makeAlarm()
        let strayID = AlarmID(ids.next())
        let stray = ScheduledAlarmSnapshot(
            alarmID: strayID, fireTime: now.addingTimeInterval(3600), isCritical: false)
        let plan = reconciler.plan(
            desired: [first, second], system: [stray], now: now, deviceTimeZone: .gmt)
        XCTAssertEqual(plan.count, 3, "two missing + one extra")
        let orderedIDs = plan.map(\.alarmID.rawValue.uuidString)
        XCTAssertEqual(orderedIDs, orderedIDs.sorted(), "repairs are ordered by target id")
    }

    func testFixedZoneAlarmUsesAnchorZoneNotDevice() throws {
        // A `.stayFixed` alarm's occurrence is anchored to its OWN zone, independent of the
        // device zone (#16). Held at that anchor-zone occurrence it must not look divergent
        // even when the device zone differs — proving the planner resolves the zone through
        // the scheduling engine, not the device zone.
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "Asia/Tokyo")))
        let epoch = Date(timeIntervalSince1970: 0)
        let alarm = try Alarm(
            id: AlarmID(ids.next()), label: "wake", isEnabled: true, schedule: schedule,
            travelBehavior: .stayFixed, criticality: .critical, createdAt: epoch, updatedAt: epoch,
            revision: 0)
        let device = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let anchored = try XCTUnwrap(
            engine.nextOccurrence(for: alarm, after: now, deviceTimeZone: device))
        let held = ScheduledAlarmSnapshot(alarmID: alarm.id, fireTime: anchored, isCritical: true)
        let plan = reconciler.plan(
            desired: [alarm], system: [held], now: now, deviceTimeZone: device)
        XCTAssertTrue(
            plan.isEmpty,
            "a fixed-zone alarm held at its anchor-zone occurrence is not divergent")
    }
}
