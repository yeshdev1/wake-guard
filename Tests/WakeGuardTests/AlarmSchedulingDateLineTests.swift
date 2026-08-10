import Foundation
import XCTest

@testable import WakeGuard

/// WG-023: International Date Line + unusual offsets. Verifies a whole-day IDL skip fires on the next
/// existing day (never lost, flagged), the 30/45-minute-offset zones (Lord Howe, Chatham) resolve DST
/// correctly, plain unusual offsets (Kathmandu +5:45, Kiritimati +14, Pago Pago −11) fire at the exact
/// wall-clock, and — a property/matrix check — every future alarm across a matrix of extreme zones has
/// exactly one strictly-future, deterministic occurrence (no unintended duplicate or skip).
final class AlarmSchedulingDateLineTests: XCTestCase {

    private let engine = AlarmSchedulingEngine()

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

    private func weekly(_ days: Set<Weekday>, at hour: Int, _ minute: Int, zone identifier: String)
        throws -> ScheduleRule
    {
        .weekly(
            WeeklySchedule(
                days: try WeekdaySet(days),
                time: try TimeOfDay(hour: hour, minute: minute),
                timeZone: try IANATimeZone(identifier: identifier)))
    }

    // MARK: - International Date Line whole-day skip

    func testDateLineWholeDaySkipFiresOnNextExistingDay() throws {
        // Pacific/Apia skipped 2011-12-30 entirely (jumped Dec 29 → Dec 31 crossing the Date Line). A
        // one-time on the nonexistent day fires at the same wall-clock on the next existing day (Dec 31),
        // flagged so a UI can explain it — never lost.
        let apia = "Pacific/Apia"
        let before = try makeDate(year: 2011, month: 12, day: 1, hour: 0, minute: 0, in: apia)
        let result = try XCTUnwrap(
            engine.resolvedNextOccurrence(
                of: try oneTime(2011, 12, 30, at: 7, 0, zone: apia), after: before,
                in: try zone(apia)))
        let comps = try calendar(apia).dateComponents(
            [.month, .day, .hour, .minute], from: result.date)
        XCTAssertEqual(comps.month, 12)
        XCTAssertEqual(comps.day, 31, "the skipped day advances to the next existing day")
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 0, "same wall-clock time")
        XCTAssertEqual(result.resolution, .skippedAcrossDateLine)
    }

    func testDateLineSkipIsNeverLostForAPastTargetNow() throws {
        // The safety point: even the skipped-day alarm resolves to a real future instant; if `now` is
        // already past it, it correctly yields nil (no phantom past fire).
        let apia = "Pacific/Apia"
        let after = try makeDate(year: 2012, month: 1, day: 1, hour: 0, minute: 0, in: apia)
        XCTAssertNil(
            engine.nextOccurrence(
                of: try oneTime(2011, 12, 30, at: 7, 0, zone: apia), after: after,
                in: try zone(apia)))
    }

    // MARK: - 45-minute-offset DST (Chatham)

    func testChathamFortyFiveMinuteOffsetSpringForwardFiresAtGapEnd() throws {
        // Chatham (+12:45 / +13:45 DST) springs forward 2026-09-27 02:45 → 03:45. A 03:00 one-time is in
        // the gap → fires at 03:45.
        let chatham = "Pacific/Chatham"
        let before = try makeDate(year: 2026, month: 9, day: 1, hour: 0, minute: 0, in: chatham)
        let result = try XCTUnwrap(
            engine.resolvedNextOccurrence(
                of: try oneTime(2026, 9, 27, at: 3, 0, zone: chatham), after: before,
                in: try zone(chatham)))
        let comps = try calendar(chatham).dateComponents([.hour, .minute], from: result.date)
        XCTAssertEqual(comps.hour, 3)
        XCTAssertEqual(comps.minute, 45, "the 45-minute-offset gap resolves to its end")
        XCTAssertEqual(result.resolution, .skippedToGapEnd)
    }

    func testChathamFortyFiveMinuteOffsetFallBackFiresAtEarlier() throws {
        // Chatham falls back 2026-04-05 03:45 → 02:45. A 03:00 one-time happens twice → fires at the
        // first (earlier +13:45) instant.
        let chatham = "Pacific/Chatham"
        let before = try makeDate(year: 2026, month: 4, day: 1, hour: 0, minute: 0, in: chatham)
        let result = try XCTUnwrap(
            engine.resolvedNextOccurrence(
                of: try oneTime(2026, 4, 5, at: 3, 0, zone: chatham), after: before,
                in: try zone(chatham)))
        let comps = try calendar(chatham).dateComponents([.hour, .minute], from: result.date)
        XCTAssertEqual(comps.hour, 3)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(result.resolution, .ambiguousUsedFirst)
        XCTAssertEqual(
            try zone(chatham).secondsFromGMT(for: result.date), 13 * 3_600 + 45 * 60,
            "earlier (+13:45) instant")
    }

    // MARK: - Plain unusual offsets

    func testUnusualFixedOffsetsFireAtTheCorrectInstant() throws {
        // Kathmandu +5:45, Kiritimati +14, Pago Pago −11 — plain offsets the calendar applies; a 07:00
        // one-time fires at exactly that wall-clock, no adjustment.
        let cases: [(String, Int)] = [
            ("Asia/Kathmandu", 5 * 3_600 + 45 * 60), ("Pacific/Kiritimati", 14 * 3_600),
            ("Pacific/Pago_Pago", -11 * 3_600),
        ]
        for (zoneID, offset) in cases {
            let before = try makeDate(year: 2026, month: 7, day: 1, hour: 0, minute: 0, in: zoneID)
            let result = try XCTUnwrap(
                engine.resolvedNextOccurrence(
                    of: try oneTime(2026, 7, 15, at: 7, 0, zone: zoneID), after: before,
                    in: try zone(zoneID)), "\(zoneID) should have a next occurrence")
            let comps = try calendar(zoneID).dateComponents([.hour, .minute], from: result.date)
            XCTAssertEqual(comps.hour, 7, zoneID)
            XCTAssertEqual(comps.minute, 0, zoneID)
            XCTAssertEqual(result.resolution, .exact, zoneID)
            XCTAssertEqual(
                try zone(zoneID).secondsFromGMT(for: result.date), offset, "\(zoneID) offset")
        }
    }

    // MARK: - Property / matrix: no unintended duplicate or skipped occurrence

    func testMatrixOfExtremeZonesHasExactlyOneStrictlyFutureDeterministicOccurrence() throws {
        let zones = [
            "UTC", "America/New_York", "Europe/London", "Australia/Lord_Howe", "Pacific/Chatham",
            "Asia/Kathmandu", "Pacific/Kiritimati", "Pacific/Pago_Pago", "Pacific/Apia",
            "Asia/Tokyo",
        ]
        for zoneID in zones {
            let tz = try zone(zoneID)
            let now = try makeDate(year: 2027, month: 1, day: 15, hour: 12, minute: 0, in: zoneID)

            let oneTimeRule = try oneTime(2027, 6, 15, at: 7, 30, zone: zoneID)
            let onceA = try XCTUnwrap(
                engine.nextOccurrence(of: oneTimeRule, after: now, in: tz),
                "\(zoneID): a future one-time must have an occurrence")
            XCTAssertGreaterThan(onceA, now, "\(zoneID): strictly future")
            XCTAssertEqual(
                onceA, engine.nextOccurrence(of: oneTimeRule, after: now, in: tz),
                "\(zoneID): deterministic — no duplicate")

            let weeklyRule = try weekly(Set(Weekday.allCases), at: 7, 30, zone: zoneID)
            let weekA = try XCTUnwrap(
                engine.nextOccurrence(of: weeklyRule, after: now, in: tz),
                "\(zoneID): weekly occurrence")
            XCTAssertGreaterThan(weekA, now, "\(zoneID): weekly strictly future")
            XCTAssertEqual(
                weekA, engine.nextOccurrence(of: weeklyRule, after: now, in: tz),
                "\(zoneID): weekly deterministic")
            XCTAssertLessThanOrEqual(
                weekA.timeIntervalSince(now), 8 * 86_400,
                "\(zoneID): weekly within ~a week — never skipped")
        }
    }
}
