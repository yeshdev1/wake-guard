import Foundation
import XCTest

@testable import WakeGuard

/// WG-106: DST transition **during travel**. Verifies travel-zone selection (WG-021/104) composes with
/// the explicit DST policy (WG-022) — a follow-local alarm resolves in the **destination** zone, a
/// stay-fixed alarm in the **anchor** zone — and that the resulting **ambiguity is surfaced** (the
/// `DSTResolution`, incl. through the WG-105 travel prompt). A matrix over behavior × DST scenario.
///
/// US DST 2026: spring-forward Sun 2026-03-08 (02:00→03:00), fall-back Sun 2026-11-01 (02:00→01:00);
/// Asia/Tokyo observes no DST — the composition contrast.
final class TravelDSTCompositionTests: XCTestCase {

    private let engine = AlarmSchedulingEngine()
    private let evaluator = TravelPolicyEvaluator()
    private let builder = TimeZoneChangePromptBuilder()

    // MARK: helpers

    private func iana(_ identifier: String) throws -> IANATimeZone {
        try IANATimeZone(identifier: identifier)
    }

    private func makeDate(
        _ year: Int, _ month: Int, _ day: Int, in identifier: String
    ) throws -> Date {
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
                time: try TimeOfDay(hour: hour, minute: minute),
                timeZone: try iana(identifier)))
    }

    /// Resolve `schedule`'s next occurrence after `now` in the zone the alarm's `behavior` selects —
    /// composing WG-021/104 zone selection with the WG-022 DST resolution.
    private func resolvedUnderTravel(
        _ schedule: ScheduleRule, behavior: TravelBehavior, anchor: IANATimeZone,
        device: IANATimeZone, now: Date
    ) throws -> (date: Date, resolution: DSTResolution) {
        let zone = engine.schedulingTimeZone(
            for: behavior, anchor: anchor, deviceTimeZone: device.timeZone)
        return try XCTUnwrap(engine.resolvedNextOccurrence(of: schedule, after: now, in: zone))
    }

    private func assertRingWallClock(
        _ date: Date?, hour: Int, minute: Int, in identifier: String, line: UInt = #line
    ) throws {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
        let components = value.dateComponents([.hour, .minute], from: try XCTUnwrap(date))
        XCTAssertEqual(components.hour, hour, line: line)
        XCTAssertEqual(components.minute, minute, line: line)
    }

    // MARK: matrix — travel behavior × DST scenario

    func testFollowLocalIntoSpringForwardGapFiresAtGapEnd() throws {
        // 02:30 doesn't exist at the destination that night — it fires at the gap's end (03:00), flagged.
        let resolved = try resolvedUnderTravel(
            try oneTime(2026, 3, 8, at: 2, 30, zone: "Asia/Tokyo"), behavior: .followLocal,
            anchor: try iana("Asia/Tokyo"), device: try iana("America/New_York"),
            now: try makeDate(2026, 3, 1, in: "UTC"))
        XCTAssertEqual(resolved.resolution, .skippedToGapEnd)
        try assertRingWallClock(resolved.date, hour: 3, minute: 0, in: "America/New_York")
    }

    func testFollowLocalIntoFallBackDuplicateFiresAtEarlierInstant() throws {
        // 01:30 happens twice at the destination that night — it fires at the first (earlier) one.
        let resolved = try resolvedUnderTravel(
            try oneTime(2026, 11, 1, at: 1, 30, zone: "Asia/Tokyo"), behavior: .followLocal,
            anchor: try iana("Asia/Tokyo"), device: try iana("America/New_York"),
            now: try makeDate(2026, 10, 25, in: "UTC"))
        XCTAssertEqual(resolved.resolution, .ambiguousUsedFirst)
        try assertRingWallClock(resolved.date, hour: 1, minute: 30, in: "America/New_York")
    }

    func testStayFixedResolvesDSTInTheAnchorZoneNotTheDevice() throws {
        // The SAME 02:30 wall-clock: a gap under stay-fixed (interpreted in the New York anchor) but
        // exact under follow-local (interpreted in the DST-free Tokyo device) — travel selects the zone,
        // and DST is resolved in whichever zone that is.
        let schedule = try oneTime(2026, 3, 8, at: 2, 30, zone: "America/New_York")
        let now = try makeDate(2026, 3, 1, in: "UTC")
        let fixed = try resolvedUnderTravel(
            schedule, behavior: .stayFixed, anchor: try iana("America/New_York"),
            device: try iana("Asia/Tokyo"), now: now)
        XCTAssertEqual(fixed.resolution, .skippedToGapEnd)
        try assertRingWallClock(fixed.date, hour: 3, minute: 0, in: "America/New_York")

        let local = try resolvedUnderTravel(
            schedule, behavior: .followLocal, anchor: try iana("America/New_York"),
            device: try iana("Asia/Tokyo"), now: now)
        XCTAssertEqual(local.resolution, .exact)
        try assertRingWallClock(local.date, hour: 2, minute: 30, in: "Asia/Tokyo")
    }

    func testNonTransitionDayResolvesExactUnderTravel() throws {
        let resolved = try resolvedUnderTravel(
            try oneTime(2026, 6, 15, at: 7, 0, zone: "Asia/Tokyo"), behavior: .followLocal,
            anchor: try iana("Asia/Tokyo"), device: try iana("America/New_York"),
            now: try makeDate(2026, 6, 1, in: "UTC"))
        XCTAssertEqual(resolved.resolution, .exact)
    }

    // MARK: the travel prompt surfaces destination-zone DST ambiguity (WG-105 + WG-106)

    func testTravelPromptSurfacesDestinationGapWhileAnchorStaysExact() throws {
        let schedule = try oneTime(2026, 3, 8, at: 2, 30, zone: "Asia/Tokyo")
        let now = try makeDate(2026, 3, 1, in: "UTC")
        let zoneChange = TimeZoneChange(
            previous: try iana("Asia/Tokyo"), current: try iana("America/New_York"))
        let alarm = try Alarm(
            id: AlarmID(try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))),
            label: "Wake", schedule: schedule, travelBehavior: .askOnChange, criticality: .standard,
            createdAt: try makeDate(2020, 1, 1, in: "UTC"),
            updatedAt: try makeDate(2020, 1, 1, in: "UTC"))
        let decision = evaluator.evaluate(
            travel: TravelContext(zoneChange: zoneChange, detectedAt: now, location: nil),
            behavior: .askOnChange, anchorZone: try iana("Asia/Tokyo"))
        let prompt = try XCTUnwrap(
            builder.makePrompt(for: alarm, decision: decision, zoneChange: zoneChange, now: now))
        // Follow-local previews the destination gap (fires 03:00 New York); keep-anchor is exact in Tokyo.
        XCTAssertEqual(prompt.alternativeOption.dstResolution, .skippedToGapEnd)
        try assertRingWallClock(
            prompt.alternativeOption.nextRing, hour: 3, minute: 0, in: "America/New_York")
        XCTAssertEqual(prompt.standingOption.dstResolution, .exact)
        try assertRingWallClock(
            prompt.standingOption.nextRing, hour: 2, minute: 30, in: "Asia/Tokyo")
    }
}
