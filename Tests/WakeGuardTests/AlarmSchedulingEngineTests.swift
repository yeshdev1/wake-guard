import Foundation
import XCTest

@testable import WakeGuard

/// WG-020: the pure next-occurrence calculator — deterministic one-time and
/// weekly calculation with an injected clock (`now`) and time zone, including
/// month/year boundaries.
final class AlarmSchedulingEngineTests: XCTestCase {

    private let engine = AlarmSchedulingEngine()

    // MARK: helpers

    private func zone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier))
    }

    private func calendar(_ identifier: String) throws -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = try zone(identifier)
        return value
    }

    // swiftlint:disable:next function_parameter_count
    private func makeDate(
        year: Int, month: Int, day: Int, hour: Int, minute: Int, in identifier: String
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return try XCTUnwrap(calendar(identifier).date(from: components))
    }

    // swiftlint:disable:next function_parameter_count
    private func oneTime(
        _ year: Int, _ month: Int, _ day: Int, at hour: Int, _ minute: Int, zone identifier: String
    ) throws -> ScheduleRule {
        .oneTime(
            OneTimeSchedule(
                date: try CalendarDate(year: year, month: month, day: day),
                time: try TimeOfDay(hour: hour, minute: minute),
                timeZone: try IANATimeZone(identifier: identifier)))
    }

    private func weekly(
        _ days: Set<Weekday>, at hour: Int, _ minute: Int, zone identifier: String
    ) throws -> ScheduleRule {
        .weekly(
            WeeklySchedule(
                days: try WeekdaySet(days),
                time: try TimeOfDay(hour: hour, minute: minute),
                timeZone: try IANATimeZone(identifier: identifier)))
    }

    // MARK: one-time

    func testOneTimeFutureReturnsInstant() throws {
        let now = Date(timeIntervalSince1970: 0)
        let rule = try oneTime(2026, 8, 15, at: 6, 30, zone: "UTC")
        let expected = try makeDate(year: 2026, month: 8, day: 15, hour: 6, minute: 30, in: "UTC")
        XCTAssertEqual(engine.nextOccurrence(of: rule, after: now, in: try zone("UTC")), expected)
    }

    func testOneTimePastReturnsNil() throws {
        let now = try makeDate(year: 2026, month: 9, day: 1, hour: 0, minute: 0, in: "UTC")
        let rule = try oneTime(2026, 8, 15, at: 6, 30, zone: "UTC")
        XCTAssertNil(engine.nextOccurrence(of: rule, after: now, in: try zone("UTC")))
    }

    func testOneTimeExactlyNowReturnsNil() throws {
        let instant = try makeDate(year: 2026, month: 8, day: 15, hour: 6, minute: 30, in: "UTC")
        let rule = try oneTime(2026, 8, 15, at: 6, 30, zone: "UTC")
        XCTAssertNil(
            engine.nextOccurrence(of: rule, after: instant, in: try zone("UTC")),
            "an occurrence exactly at now is not the next occurrence")
    }

    // MARK: weekly

    func testWeeklySingleDayProperties() throws {
        let now = try makeDate(year: 2026, month: 8, day: 3, hour: 12, minute: 0, in: "UTC")
        let rule = try weekly([.wednesday], at: 7, 0, zone: "UTC")
        let result = try XCTUnwrap(engine.nextOccurrence(of: rule, after: now, in: try zone("UTC")))
        XCTAssertGreaterThan(result, now)
        let comps = try calendar("UTC").dateComponents([.weekday, .hour, .minute], from: result)
        XCTAssertEqual(comps.weekday, Weekday.wednesday.rawValue)
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertLessThanOrEqual(result.timeIntervalSince(now), 7 * 86_400)
    }

    func testWeeklyMultipleDaysReturnsEarliest() throws {
        let now = try makeDate(year: 2026, month: 8, day: 5, hour: 12, minute: 0, in: "UTC")
        let utc = try zone("UTC")
        let both = try XCTUnwrap(
            engine.nextOccurrence(
                of: try weekly([.monday, .friday], at: 7, 0, zone: "UTC"), after: now, in: utc))
        let monday = try XCTUnwrap(
            engine.nextOccurrence(
                of: try weekly([.monday], at: 7, 0, zone: "UTC"), after: now, in: utc))
        let friday = try XCTUnwrap(
            engine.nextOccurrence(
                of: try weekly([.friday], at: 7, 0, zone: "UTC"), after: now, in: utc))
        XCTAssertEqual(both, min(monday, friday))
    }

    func testWeeklyMonthBoundary() throws {
        // A daily 07:00 alarm at Aug 31 23:00 next fires Sep 1 07:00.
        let now = try makeDate(year: 2026, month: 8, day: 31, hour: 23, minute: 0, in: "UTC")
        let rule = try weekly(Set(Weekday.allCases), at: 7, 0, zone: "UTC")
        let expected = try makeDate(year: 2026, month: 9, day: 1, hour: 7, minute: 0, in: "UTC")
        XCTAssertEqual(engine.nextOccurrence(of: rule, after: now, in: try zone("UTC")), expected)
    }

    func testWeeklyYearBoundary() throws {
        let now = try makeDate(year: 2026, month: 12, day: 31, hour: 23, minute: 0, in: "UTC")
        let rule = try weekly(Set(Weekday.allCases), at: 7, 0, zone: "UTC")
        let expected = try makeDate(year: 2027, month: 1, day: 1, hour: 7, minute: 0, in: "UTC")
        XCTAssertEqual(engine.nextOccurrence(of: rule, after: now, in: try zone("UTC")), expected)
    }

    // MARK: injection of zone and clock

    func testInjectedZoneDeterminesInstant() throws {
        let now = Date(timeIntervalSince1970: 0)
        // The rule is anchored to UTC, but the *injected* zone is what the engine
        // interprets the wall-clock in (WG-021 decides which zone to inject).
        let rule = try oneTime(2026, 8, 15, at: 7, 0, zone: "UTC")
        let inNewYork = engine.nextOccurrence(
            of: rule, after: now, in: try zone("America/New_York"))
        let inTokyo = engine.nextOccurrence(of: rule, after: now, in: try zone("Asia/Tokyo"))
        XCTAssertEqual(
            inNewYork,
            try makeDate(year: 2026, month: 8, day: 15, hour: 7, minute: 0, in: "America/New_York"))
        XCTAssertEqual(
            inTokyo,
            try makeDate(year: 2026, month: 8, day: 15, hour: 7, minute: 0, in: "Asia/Tokyo"))
        XCTAssertNotEqual(
            inNewYork, inTokyo, "same wall-clock in different zones -> different instants")
    }

    func testClockInjectionViaTestClock() throws {
        let clock = TestClock(
            now: try makeDate(year: 2026, month: 8, day: 3, hour: 6, minute: 0, in: "UTC"))
        let rule = try weekly(Set(Weekday.allCases), at: 7, 0, zone: "UTC")
        let utc = try zone("UTC")

        // At 06:00, today's 07:00 is still ahead.
        XCTAssertEqual(
            engine.nextOccurrence(of: rule, after: clock.now, in: utc),
            try makeDate(year: 2026, month: 8, day: 3, hour: 7, minute: 0, in: "UTC"))

        // Advance past 07:00 -> next fire is tomorrow 07:00.
        clock.advance(by: 2 * 3_600)
        XCTAssertEqual(
            engine.nextOccurrence(of: rule, after: clock.now, in: utc),
            try makeDate(year: 2026, month: 8, day: 4, hour: 7, minute: 0, in: "UTC"))
    }

    func testDeterministicAcrossRepeatedCalls() throws {
        let now = try makeDate(year: 2026, month: 8, day: 3, hour: 12, minute: 0, in: "UTC")
        let rule = try weekly([.tuesday, .thursday], at: 6, 15, zone: "UTC")
        let utc = try zone("UTC")
        XCTAssertEqual(
            engine.nextOccurrence(of: rule, after: now, in: utc),
            engine.nextOccurrence(of: rule, after: now, in: utc))
    }

    // MARK: DST characterization (explicit policy is WG-022; these pin the current
    // resolution so a regression that silently skips/duplicates is caught).

    func testSpringForwardWeeklyResolvesForwardNotSkipped() throws {
        // 2026-03-08 02:30 America/New_York does not exist (spring forward). A weekly
        // Sunday 02:30 rule must NOT skip a week; `.nextTime` resolves to 03:00.
        let newYork = "America/New_York"
        let now = try makeDate(year: 2026, month: 3, day: 7, hour: 12, minute: 0, in: newYork)
        let rule = try weekly([.sunday], at: 2, 30, zone: newYork)
        let result = try XCTUnwrap(
            engine.nextOccurrence(of: rule, after: now, in: try zone(newYork)))
        let comps = try calendar(newYork).dateComponents(
            [.month, .day, .hour, .minute], from: result)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 8, "resolved same day, not skipped to next week")
        XCTAssertEqual(comps.hour, 3)
        XCTAssertEqual(comps.minute, 0)
    }

    func testSpringForwardOneTimeResolvesForwardNotSkipped() throws {
        // Same nonexistent 02:30; one-time resolves to 03:30 (a documented divergence
        // from weekly's 03:00 — WG-022 converges them). The point: it does not skip.
        let newYork = "America/New_York"
        let before = try makeDate(year: 2026, month: 3, day: 1, hour: 0, minute: 0, in: newYork)
        let rule = try oneTime(2026, 3, 8, at: 2, 30, zone: newYork)
        let result = try XCTUnwrap(
            engine.nextOccurrence(of: rule, after: before, in: try zone(newYork)))
        let comps = try calendar(newYork).dateComponents([.day, .hour, .minute], from: result)
        XCTAssertEqual(comps.day, 8)
        XCTAssertEqual(comps.hour, 3)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFallBackWeeklyReturnsEarlierInstant() throws {
        // 2026-11-01 01:30 America/New_York occurs twice (fall back). The engine
        // returns the earlier (EDT, UTC-4) instant. Dedup across the repeated hour
        // when *enumerating* is a WG-026/WG-029 concern (see DECISIONS).
        let newYork = "America/New_York"
        let before = try makeDate(year: 2026, month: 10, day: 30, hour: 0, minute: 0, in: newYork)
        let rule = try weekly([.sunday], at: 1, 30, zone: newYork)
        let result = try XCTUnwrap(
            engine.nextOccurrence(of: rule, after: before, in: try zone(newYork)))
        let comps = try calendar(newYork).dateComponents([.hour, .minute], from: result)
        XCTAssertEqual(comps.hour, 1)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertEqual(
            try zone(newYork).secondsFromGMT(for: result), -4 * 3_600,
            "earlier (EDT) instant of the repeated hour")
    }
}
