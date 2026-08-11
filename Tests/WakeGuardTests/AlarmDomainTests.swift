import Foundation
import XCTest

@testable import WakeGuard

/// WG-010: the alarm domain models — valid construction, rejection of invalid
/// states (at init *and* at decode), the always-available accessible fallback,
/// and Codable round-tripping.
final class AlarmDomainTests: XCTestCase {

    /// A fully-populated, valid critical alarm, built with the WG-007
    /// deterministic clock + id generator.
    private func makeValidAlarm() throws -> Alarm {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let ids = DeterministicIDGenerator(seed: 7)
        let timeZone = try IANATimeZone(identifier: "America/New_York")
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet([.monday, .wednesday, .friday]),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: timeZone))
        let walk = try WalkChallenge(
            targetDuration: 10, minimumSteps: 12, maximumCadence: 4,
            allowedPauses: 1, antiCheatThreshold: 0.7, accessibleFallback: .tapSequence)
        return try Alarm(
            id: AlarmID(ids.next()),
            label: "Work",
            schedule: schedule,
            travelBehavior: .stayFixed,
            criticality: .critical,
            snoozePolicy: try .enabled(interval: 540, maximumCount: 3),
            challengePolicy: .walk(walk),
            preAlarmPolicy: try .enabled(leadTime: 1_800),
            createdAt: clock.now,
            updatedAt: clock.now,
            revision: 0)
    }

    func testValidAlarmConstructs() throws {
        let alarm = try makeValidAlarm()
        XCTAssertEqual(alarm.criticality, .critical)
        XCTAssertEqual(alarm.schedule.time, try TimeOfDay(hour: 7, minute: 0))
        XCTAssertEqual(alarm.schedule.anchorTimeZone.identifier, "America/New_York")
    }

    // MARK: invalid states are rejected at construction

    func testTimeOfDayRejectsOutOfRange() {
        XCTAssertThrowsError(try TimeOfDay(hour: 24, minute: 0))
        XCTAssertThrowsError(try TimeOfDay(hour: 0, minute: 60))
        XCTAssertThrowsError(try TimeOfDay(hour: -1, minute: 0))
    }

    func testCalendarDateRejectsImpossibleDate() {
        XCTAssertThrowsError(try CalendarDate(year: 2026, month: 2, day: 30))
        XCTAssertThrowsError(try CalendarDate(year: 2026, month: 13, day: 1))
        XCTAssertNoThrow(try CalendarDate(year: 2028, month: 2, day: 29))  // leap day is valid
    }

    func testWeekdaySetRejectsEmpty() {
        XCTAssertThrowsError(try WeekdaySet([]))
        XCTAssertNoThrow(try WeekdaySet([.monday]))
    }

    func testIANATimeZoneRejectsOffsetsAndBogusButKeepsRealZones() {
        // The whole fixed-offset GMT family — including the `Etc/GMT±N` offset zones (WG-242) — and
        // unresolvable ids are rejected (#11): they carry an offset with no DST/geographic identity.
        let rejected = [
            "GMT", "GMT+0", "GMT-0", "GMT+5", "GMT+0530", "GMT+1400", "UTC+5", "Not/AZone",
            "Etc/GMT+5", "Etc/GMT-14",
        ]
        for zone in rejected {
            XCTAssertThrowsError(try IANATimeZone(identifier: zone), zone)
        }
        // Real geographic zones — plus the genuine `UTC`/`Etc/UTC`/`Etc/Universal` reference zones (which
        // are not offset-only) — are kept.
        let accepted = [
            "UTC", "Etc/UTC", "Etc/Universal", "America/New_York",
            "Asia/Kolkata", "Pacific/Kiritimati", "Asia/Kathmandu", "Australia/Eucla",
        ]
        for zone in accepted {
            XCTAssertNoThrow(try IANATimeZone(identifier: zone), zone)
        }
    }

    func testWalkChallengeRejectsNonPositiveParameters() {
        XCTAssertThrowsError(
            try WalkChallenge(
                targetDuration: 0, minimumSteps: 1, maximumCadence: 1,
                allowedPauses: 0, antiCheatThreshold: 0, accessibleFallback: .tapSequence))
        XCTAssertThrowsError(
            try WalkChallenge(
                targetDuration: 10, minimumSteps: 0, maximumCadence: 1,
                allowedPauses: 0, antiCheatThreshold: 0, accessibleFallback: .tapSequence))
    }

    func testSnoozeAndPreAlarmValidation() {
        XCTAssertThrowsError(try SnoozePolicy.enabled(interval: 0, maximumCount: 1))
        XCTAssertThrowsError(try SnoozePolicy.enabled(interval: 60, maximumCount: 0))
        XCTAssertThrowsError(try PreAlarmPolicy.enabled(leadTime: 0))
        XCTAssertEqual(SnoozePolicy.disabled.isEnabled, false)
    }

    func testAlarmRejectsBadInvariants() throws {
        let timeZone = try IANATimeZone(identifier: "UTC")
        let schedule = ScheduleRule.oneTime(
            OneTimeSchedule(
                date: try CalendarDate(year: 2026, month: 8, day: 15),
                time: try TimeOfDay(hour: 6, minute: 30),
                timeZone: timeZone))
        XCTAssertThrowsError(
            try Alarm(
                id: AlarmID(UUID()), label: "x", schedule: schedule,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 0)),
            "updatedAt before createdAt must be rejected")
        XCTAssertThrowsError(
            try Alarm(
                id: AlarmID(UUID()), label: "x", schedule: schedule,
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0), revision: -1),
            "negative revision must be rejected")
    }

    // MARK: accessible fallback guarantee (SCOPE §2.3)

    func testWalkChallengeAlwaysHasAccessibleFallback() throws {
        let walk = try WalkChallenge(
            targetDuration: 10, minimumSteps: 12, maximumCadence: 4,
            allowedPauses: 1, antiCheatThreshold: 0.7, accessibleFallback: .pressAndHold)
        let policy = ChallengePolicy.walk(walk)
        XCTAssertTrue(policy.isRequired)
        XCTAssertEqual(policy.accessibleFallback, .pressAndHold)
        XCTAssertFalse(ChallengePolicy.none.isRequired)
        XCTAssertNil(ChallengePolicy.none.accessibleFallback)
    }

    // MARK: Codable

    func testAlarmCodableRoundTrips() throws {
        let alarm = try makeValidAlarm()
        let data = try JSONEncoder().encode(alarm)
        let decoded = try JSONDecoder().decode(Alarm.self, from: data)
        XCTAssertEqual(alarm, decoded)
    }

    func testDecodingRejectsInvalidTimeOfDay() {
        let json = Data(#"{"hour":25,"minute":0}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(TimeOfDay.self, from: json))
    }

    func testDecodingRejectsNonIANATimeZone() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(IANATimeZone.self, from: Data("\"GMT+5\"".utf8)))
        XCTAssertThrowsError(
            try JSONDecoder().decode(IANATimeZone.self, from: Data("\"GMT\"".utf8)))
    }

    func testDecodingReValidatesPolicyLeaves() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                SnoozePolicy.self,
                from: Data(#"{"isEnabled":true,"interval":0,"maximumCount":1}"#.utf8)),
            "enabled snooze with zero interval must be rejected on decode")
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                PreAlarmPolicy.self,
                from: Data(#"{"isEnabled":true,"leadTime":0}"#.utf8)),
            "enabled pre-alarm with zero lead time must be rejected on decode")
    }

    func testDecodingReValidatesNestedAndCrossFieldInvariants() throws {
        // Corrupt a valid WalkChallenge's minimumSteps -> decode must re-validate.
        let walk = try WalkChallenge(
            targetDuration: 10, minimumSteps: 5, maximumCadence: 1,
            allowedPauses: 0, antiCheatThreshold: 0, accessibleFallback: .tapSequence)
        var walkObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(walk)) as? [String: Any])
        walkObject["minimumSteps"] = 0
        let corruptedWalk = try JSONSerialization.data(withJSONObject: walkObject)
        XCTAssertThrowsError(try JSONDecoder().decode(WalkChallenge.self, from: corruptedWalk))

        // Corrupt a valid Alarm's revision -> decode must re-run cross-field checks.
        let alarm = try makeValidAlarm()
        var alarmObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(alarm)) as? [String: Any])
        alarmObject["revision"] = -1
        let corruptedAlarm = try JSONSerialization.data(withJSONObject: alarmObject)
        XCTAssertThrowsError(try JSONDecoder().decode(Alarm.self, from: corruptedAlarm))
    }
}
