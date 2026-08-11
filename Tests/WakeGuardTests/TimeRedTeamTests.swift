import Foundation
import XCTest

@testable import WakeGuard

/// WG-242 (Epoch 3) time/DST/recurrence regression tests. Pins the load-bearing **fall-back anti-double-fire**
/// behaviour the DECISIONS log flags (a recurring alarm at a local time that occurs twice must advance to the
/// next day, never re-fire at the repeated instant), and the tightened `Etc/GMT±N` rejection (#11).
final class TimeRedTeamTests: XCTestCase {

    private let engine = AlarmSchedulingEngine()

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws
        -> Date
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        return try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
            ))
    }

    /// 2026-11-01 America/New_York: clocks fall back 02:00 EDT → 01:00 EST, so **01:30 occurs twice** —
    /// 01:30 EDT (05:30 UTC) then 01:30 EST (06:30 UTC). A daily alarm asked at 06:00 UTC (between the two)
    /// must NOT return the second 01:30; it advances to the next day.
    func testFallBackRepeatedHourDoesNotDoubleFire() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let rule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 1, minute: 30),
                timeZone: try IANATimeZone(identifier: "America/New_York")))

        // 01:00 EST — after the first 01:30 (05:30 UTC), before the second (06:30 UTC).
        let now = try utcDate(2026, 11, 1, 6, 0)
        // The repeated 01:30 EST that a naive scheduler would double-fire at.
        let secondInstant = try utcDate(2026, 11, 1, 6, 30)
        // 01:30 EST the following day — the correct next occurrence.
        let nextDay = try utcDate(2026, 11, 2, 6, 30)

        let next = try XCTUnwrap(engine.nextOccurrence(of: rule, after: now, in: zone))

        XCTAssertNotEqual(next, secondInstant, "must not re-fire at the repeated fall-back instant")
        XCTAssertEqual(
            next, nextDay, "advances to the next day's 01:30, never twice on the fall-back day")
    }

    func testEtcGmtOffsetZonesAreRejected() {
        // Signed non-zero offset zones (POSIX-inverted, no DST) are rejected (#11).
        for offsetZone in ["Etc/GMT+5", "Etc/GMT-14", "Etc/GMT+12"] {
            XCTAssertThrowsError(
                try IANATimeZone(identifier: offsetZone),
                "\(offsetZone) is offset-only (no DST/geography) and must be rejected (#11)")
        }
        // The genuine zero-offset reference zones remain valid.
        XCTAssertNoThrow(try IANATimeZone(identifier: "UTC"))
        XCTAssertNoThrow(try IANATimeZone(identifier: "Etc/UTC"))
    }
}
