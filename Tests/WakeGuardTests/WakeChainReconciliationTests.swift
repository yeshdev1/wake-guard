import Foundation
import XCTest

@testable import WakeGuard

/// WG-291: the reconciler treats the wake chain as first-class desired state — the family is placed with
/// the occurrence, matches idempotently, is never touched while its ring window is live (a pass explicitly
/// cancelled it / an unsatisfied wake still needs it), and reaps as ordinary extras once the window ends.
final class WakeChainReconciliationTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 292)
    private let reconciler = AlarmReconciler()
    private let zone = TimeZone.gmt

    private func makeAlarm(challenge: Bool = true) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule, criticality: .critical,
            challengePolicy: challenge ? .walk(try .standard()) : .none,
            createdAt: epoch, updatedAt: epoch)
    }

    private func iso(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    func testDesiredStateIncludesTheWholeFamilyUpfront() throws {
        let alarm = try makeAlarm()
        let now = try iso("2026-08-17T04:00:00Z")
        let repairs = reconciler.plan(desired: [alarm], system: [], now: now, deviceTimeZone: zone)

        let schedules = repairs.compactMap { repair -> AlarmScheduleRequest? in
            if case .schedule(let request) = repair { return request }
            return nil
        }
        XCTAssertEqual(
            schedules.count, 1 + RearmConfiguration.default.maxAttempts,
            "the main occurrence and every re-ring member are desired upfront (#9 — no app at ring time)"
        )
        XCTAssertEqual(schedules.filter { $0.parentAlarmID == alarm.id }.count, 15)
    }

    func testMatchingFamilyIsIdempotent() throws {
        let alarm = try makeAlarm()
        let now = try iso("2026-08-17T04:00:00Z")
        let fire = try iso("2026-08-17T07:00:00Z")
        var system = [ScheduledAlarmSnapshot(alarmID: alarm.id, fireTime: fire, isCritical: true)]
        for entry in WakeChain.requests(for: alarm, occurrence: fire) {
            system.append(
                ScheduledAlarmSnapshot(
                    alarmID: entry.alarmID, fireTime: entry.fireTime, isCritical: true))
        }
        let repairs = reconciler.plan(
            desired: [alarm], system: system, now: now, deviceTimeZone: zone)
        XCTAssertTrue(
            repairs.isEmpty, "a placed family needs no repair — reconcile never oscillates")
    }

    func testLiveFamilyIsNeverTouchedMidWindow() throws {
        let alarm = try makeAlarm()
        let fired = try iso("2026-08-17T07:00:00Z")
        let now = try iso("2026-08-17T07:10:00Z")
        // A remaining member of the fired occurrence is still in the system, mid-window.
        let member = try XCTUnwrap(WakeChain.requests(for: alarm, occurrence: fired).last)
        let system = [
            ScheduledAlarmSnapshot(
                alarmID: member.alarmID, fireTime: member.fireTime, isCritical: true)
        ]
        let repairs = reconciler.plan(
            desired: [alarm], system: system, now: now, deviceTimeZone: zone)

        XCTAssertFalse(
            repairs.contains(.cancel(member.alarmID)),
            "mid-window a live member is never reaped — reconcile must not silence an unsatisfied wake"
        )
        XCTAssertFalse(
            repairs.contains { repair in
                if case .schedule(let request) = repair {
                    return WakeChain.memberIDs(for: alarm, occurrence: fired)
                        .contains(request.alarmID)
                }
                return false
            },
            "mid-window a missing member is never re-placed — a pass explicitly cancelled it")
    }

    func testStaleFamilyReapsAsExtrasOnceTheWindowEnds() throws {
        let alarm = try makeAlarm()
        let fired = try iso("2026-08-17T07:00:00Z")
        let now = try iso("2026-08-17T07:45:00Z")  // past the 30-minute window
        let member = try XCTUnwrap(WakeChain.requests(for: alarm, occurrence: fired).last)
        let system = [
            ScheduledAlarmSnapshot(
                alarmID: member.alarmID, fireTime: member.fireTime, isCritical: true)
        ]
        let repairs = reconciler.plan(
            desired: [alarm], system: system, now: now, deviceTimeZone: zone)
        XCTAssertTrue(
            repairs.contains(.cancel(member.alarmID)),
            "after the window a leftover member is an ordinary extra")
    }
}
