import Foundation
import XCTest

@testable import WakeGuard

/// WG-107: International Date Line travel. Composes the WG-023 whole-day IDL skip with travel-zone
/// selection (WG-104) and the WG-105/106 prompt. Verifies **occurrences do not duplicate unexpectedly**
/// (one strictly-future, deterministic instant), the **user sees the date as well as the time** (a ring
/// shifted to the next existing day surfaces `.skippedAcrossDateLine` and previews the shifted date), and
/// **critical alarm behavior is explicit** (never lost across the line; a critical shift confirms, #6,
/// and no response keeps the anchor, #7).
///
/// Pacific/Apia skipped 2011-12-30 entirely (Dec 29 → Dec 31) crossing the Date Line; Asia/Tokyo is a
/// normal zone that has Dec 30 — the composition contrast.
final class TravelDateLineTests: XCTestCase {

    private let engine = AlarmSchedulingEngine()
    private let evaluator = TravelPolicyEvaluator()
    private let builder = TimeZoneChangePromptBuilder()

    // MARK: helpers

    private func iana(_ identifier: String) throws -> IANATimeZone {
        try IANATimeZone(identifier: identifier)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, in identifier: String) throws
        -> Date
    {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
        var components = DateComponents()
        (components.year, components.month, components.day) = (year, month, day)
        (components.hour, components.minute, components.second) = (0, 0, 0)
        return try XCTUnwrap(value.date(from: components))
    }

    // swiftlint:disable:next function_parameter_count
    private func oneTime(
        _ year: Int, _ month: Int, _ day: Int, at hour: Int, _ minute: Int, zone identifier: String
    ) throws -> ScheduleRule {
        .oneTime(
            OneTimeSchedule(
                date: try CalendarDate(year: year, month: month, day: day),
                time: try TimeOfDay(hour: hour, minute: minute), timeZone: try iana(identifier)))
    }

    private func resolvedUnderTravel(
        _ schedule: ScheduleRule, behavior: TravelBehavior, anchor: IANATimeZone,
        device: IANATimeZone, now: Date
    ) throws -> (date: Date, resolution: DSTResolution) {
        let zone = engine.schedulingTimeZone(
            for: behavior, anchor: anchor, deviceTimeZone: device.timeZone)
        return try XCTUnwrap(engine.resolvedNextOccurrence(of: schedule, after: now, in: zone))
    }

    private func assertRing(
        _ date: Date?, month: Int, day: Int, hour: Int, in identifier: String, line: UInt = #line
    ) throws {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
        let parts = value.dateComponents([.month, .day, .hour, .minute], from: try XCTUnwrap(date))
        XCTAssertEqual(parts.month, month, "month", line: line)
        XCTAssertEqual(parts.day, day, "day (user sees the date)", line: line)
        XCTAssertEqual(parts.hour, hour, "hour", line: line)
        XCTAssertEqual(parts.minute, 0, "minute", line: line)
    }

    private func criticalAskAlarm(schedule: ScheduleRule, criticality: Criticality) throws -> Alarm
    {
        try Alarm(
            id: AlarmID(try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-0000000000a7"))),
            label: "Wake", schedule: schedule, travelBehavior: .askOnChange,
            criticality: criticality,
            createdAt: try makeDate(2010, 1, 1, in: "UTC"),
            updatedAt: try makeDate(2010, 1, 1, in: "UTC"))
    }

    // MARK: follow-local across the Date Line fires on the next existing day (user sees the date)

    func testFollowLocalAcrossDateLineFiresOnNextExistingDay() throws {
        // The device is now in Apia; a one-time on the nonexistent 2011-12-30 fires 07:00 on Dec 31, and
        // the preview surfaces the shifted DATE — never lost, flagged.
        let resolved = try resolvedUnderTravel(
            try oneTime(2011, 12, 30, at: 7, 0, zone: "Pacific/Apia"), behavior: .followLocal,
            anchor: try iana("Asia/Tokyo"), device: try iana("Pacific/Apia"),
            now: try makeDate(2011, 12, 1, in: "UTC"))
        XCTAssertEqual(resolved.resolution, .skippedAcrossDateLine)
        try assertRing(resolved.date, month: 12, day: 31, hour: 7, in: "Pacific/Apia")
    }

    func testStayFixedResolvesDateLineInTheAnchorZoneNotTheDevice() throws {
        // The SAME 2011-12-30 07:00 alarm: date-line-shifted to Dec 31 under stay-fixed (interpreted in
        // the Apia anchor, which skips Dec 30) but exact on Dec 30 under follow-local (interpreted in the
        // Tokyo device, a normal zone) — travel selects the zone, IDL is resolved in whichever it is.
        let schedule = try oneTime(2011, 12, 30, at: 7, 0, zone: "Pacific/Apia")
        let now = try makeDate(2011, 12, 1, in: "UTC")
        let fixed = try resolvedUnderTravel(
            schedule, behavior: .stayFixed, anchor: try iana("Pacific/Apia"),
            device: try iana("Asia/Tokyo"), now: now)
        XCTAssertEqual(fixed.resolution, .skippedAcrossDateLine)
        try assertRing(fixed.date, month: 12, day: 31, hour: 7, in: "Pacific/Apia")

        let local = try resolvedUnderTravel(
            schedule, behavior: .followLocal, anchor: try iana("Pacific/Apia"),
            device: try iana("Asia/Tokyo"), now: now)
        XCTAssertEqual(local.resolution, .exact)
        try assertRing(local.date, month: 12, day: 30, hour: 7, in: "Asia/Tokyo")
    }

    // MARK: the travel prompt surfaces the shift and previews both ring dates

    func testTravelPromptSurfacesDateLineShiftAndShowsBothRingDates() throws {
        let schedule = try oneTime(2011, 12, 30, at: 7, 0, zone: "Asia/Tokyo")
        let now = try makeDate(2011, 12, 1, in: "UTC")
        let zoneChange = TimeZoneChange(
            previous: try iana("Asia/Tokyo"), current: try iana("Pacific/Apia"))
        let decision = evaluator.evaluate(
            travel: TravelContext(zoneChange: zoneChange, detectedAt: now, location: nil),
            behavior: .askOnChange, anchorZone: try iana("Asia/Tokyo"))
        let prompt = try XCTUnwrap(
            builder.makePrompt(
                for: try criticalAskAlarm(schedule: schedule, criticality: .standard),
                decision: decision, zoneChange: zoneChange, now: now))
        // Follow-local (Apia) shifts to Dec 31 and is flagged; keep-anchor (Tokyo) stays Dec 30, exact.
        XCTAssertEqual(prompt.alternativeOption.dstResolution, .skippedAcrossDateLine)
        try assertRing(
            prompt.alternativeOption.nextRing, month: 12, day: 31, hour: 7, in: "Pacific/Apia")
        XCTAssertEqual(prompt.standingOption.dstResolution, .exact)
        try assertRing(
            prompt.standingOption.nextRing, month: 12, day: 30, hour: 7, in: "Asia/Tokyo")
    }

    // MARK: critical alarm behavior is explicit (#6/#7) — never lost across the line

    func testCriticalAlarmAcrossDateLineIsNeverLostAndConfirmsToShift() throws {
        let schedule = try oneTime(2011, 12, 30, at: 7, 0, zone: "Asia/Tokyo")
        let now = try makeDate(2011, 12, 1, in: "UTC")
        let zoneChange = TimeZoneChange(
            previous: try iana("Asia/Tokyo"), current: try iana("Pacific/Apia"))
        let decision = evaluator.evaluate(
            travel: TravelContext(zoneChange: zoneChange, detectedAt: now, location: nil),
            behavior: .askOnChange, anchorZone: try iana("Asia/Tokyo"))
        let prompt = try XCTUnwrap(
            builder.makePrompt(
                for: try criticalAskAlarm(schedule: schedule, criticality: .critical),
                decision: decision, zoneChange: zoneChange, now: now))
        // Never lost: both options still resolve to a real future instant.
        XCTAssertNotNil(prompt.alternativeOption.nextRing)
        XCTAssertNotNil(prompt.standingOption.nextRing)
        // A critical shift across the line confirms (#6); no response keeps the anchor (#7).
        XCTAssertEqual(prompt.resolve(.followLocal(confirmed: false)), .needsConfirmation)
        XCTAssertEqual(prompt.resolve(.noResponse), .keepAsDocumented(.keepAnchorZone))
    }

    // MARK: occurrences do not duplicate unexpectedly

    func testDateLineTravelYieldsExactlyOneDeterministicOccurrence() throws {
        let schedule = try oneTime(2011, 12, 30, at: 7, 0, zone: "Pacific/Apia")
        let now = try makeDate(2011, 12, 1, in: "UTC")
        let first = try resolvedUnderTravel(
            schedule, behavior: .followLocal, anchor: try iana("Asia/Tokyo"),
            device: try iana("Pacific/Apia"), now: now)
        let second = try resolvedUnderTravel(
            schedule, behavior: .followLocal, anchor: try iana("Asia/Tokyo"),
            device: try iana("Pacific/Apia"), now: now)
        XCTAssertGreaterThan(first.date, now, "strictly future")
        XCTAssertEqual(first.date, second.date, "deterministic — the crossing yields no duplicate")
    }
}
