import AlarmKit
import XCTest

@testable import WakeGuard

/// WG-026: the domain→AlarmKit schedule mapping. Both supported schedule types map
/// through one per-occurrence path — the pure engine computes the next occurrence and
/// the mapper wraps it in `.fixed` — so the tests cover one-time (future and past) and
/// weekly (occurrence today vs tomorrow), plus identity external-id correlation.
final class AlarmKitScheduleMapperTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 26)
    private let mapper = AlarmKitScheduleMapper()

    private func iso(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    func testOneTimeMapsToFixedInstant() throws {
        let schedule = OneTimeSchedule(
            date: try CalendarDate(year: 2026, month: 8, day: 15),
            time: try TimeOfDay(hour: 7, minute: 0),
            timeZone: try IANATimeZone(identifier: "UTC"))
        let result = try XCTUnwrap(
            mapper.schedule(
                for: .oneTime(schedule), after: try iso("2026-08-01T00:00:00Z"), in: .gmt))
        XCTAssertEqual(result, .fixed(try iso("2026-08-15T07:00:00Z")))
    }

    func testPastOneTimeHasNoOccurrence() throws {
        let schedule = OneTimeSchedule(
            date: try CalendarDate(year: 2026, month: 8, day: 15),
            time: try TimeOfDay(hour: 7, minute: 0),
            timeZone: try IANATimeZone(identifier: "UTC"))
        let result = mapper.schedule(
            for: .oneTime(schedule), after: try iso("2026-08-20T00:00:00Z"), in: .gmt)
        XCTAssertNil(result, "a past one-time alarm has no next occurrence to schedule")
    }

    func testWeeklyMapsToFixedTodayWhenTimeStillAhead() throws {
        let schedule = WeeklySchedule(
            days: try WeekdaySet(Set(Weekday.allCases)),
            time: try TimeOfDay(hour: 7, minute: 0),
            timeZone: try IANATimeZone(identifier: "UTC"))
        let result = try XCTUnwrap(
            mapper.schedule(
                for: .weekly(schedule), after: try iso("2026-08-15T05:00:00Z"), in: .gmt))
        XCTAssertEqual(result, .fixed(try iso("2026-08-15T07:00:00Z")))
    }

    func testWeeklyMapsToFixedTomorrowWhenTimePassed() throws {
        let schedule = WeeklySchedule(
            days: try WeekdaySet(Set(Weekday.allCases)),
            time: try TimeOfDay(hour: 7, minute: 0),
            timeZone: try IANATimeZone(identifier: "UTC"))
        let result = try XCTUnwrap(
            mapper.schedule(
                for: .weekly(schedule), after: try iso("2026-08-15T09:00:00Z"), in: .gmt))
        XCTAssertEqual(result, .fixed(try iso("2026-08-16T07:00:00Z")))
    }

    func testExternalIdentifierIsTheAlarmUUID() {
        let id = AlarmID(ids.next())
        XCTAssertEqual(mapper.alarmKitID(for: id), id.rawValue)
    }
}
