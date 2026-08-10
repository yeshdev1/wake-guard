import Foundation
import XCTest

@testable import WakeGuard

/// WG-105: the time-zone-change prompt. Verifies the prompt **previews old/new ring times** (the next
/// ring under keep-anchor vs follow-local, each in its own zone), that **no response preserves the
/// documented default** (keep the anchor, #7), that a **critical change confirms** (#6), and that a
/// deterministic (non-ask) policy surfaces no prompt.
final class TimeZoneChangePromptTests: XCTestCase {

    private let builder = TimeZoneChangePromptBuilder()
    private let evaluator = TravelPolicyEvaluator()

    // MARK: helpers

    private func iana(_ identifier: String) throws -> IANATimeZone {
        try IANATimeZone(identifier: identifier)
    }

    private func makeDate(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, in identifier: String
    ) throws -> Date {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
        var components = DateComponents()
        (components.year, components.month, components.day) = (year, month, day)
        (components.hour, components.minute, components.second) = (hour, 0, 0)
        return try XCTUnwrap(value.date(from: components))
    }

    /// A one-time 07:00 alarm anchored to Asia/Tokyo, `askOnChange`, with the given criticality.
    private func alarm(
        year: Int, month: Int, day: Int, criticality: Criticality
    ) throws -> Alarm {
        let schedule = ScheduleRule.oneTime(
            OneTimeSchedule(
                date: try CalendarDate(year: year, month: month, day: day),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try iana("Asia/Tokyo")))
        let stamp = try makeDate(2020, 1, 1, 0, in: "UTC")
        return try Alarm(
            id: AlarmID(try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))),
            label: "Wake", schedule: schedule, travelBehavior: .askOnChange,
            criticality: criticality, createdAt: stamp, updatedAt: stamp)
    }

    private func tokyoToNewYork() throws -> TimeZoneChange {
        TimeZoneChange(previous: try iana("Asia/Tokyo"), current: try iana("America/New_York"))
    }

    /// The `.prompt` decision an `askOnChange` alarm produces (via the real WG-104 evaluator).
    private func askDecision() throws -> TravelPolicyDecision {
        evaluator.evaluate(
            travel: TravelContext(
                zoneChange: try tokyoToNewYork(),
                detectedAt: try makeDate(2026, 8, 15, 0, in: "UTC"),
                location: nil),
            behavior: .askOnChange, anchorZone: try iana("Asia/Tokyo"))
    }

    private func makePrompt(criticality: Criticality) throws -> TimeZoneChangePrompt {
        try XCTUnwrap(
            builder.makePrompt(
                for: try alarm(year: 2026, month: 9, day: 1, criticality: criticality),
                decision: try askDecision(),
                zoneChange: try tokyoToNewYork(), now: try makeDate(2026, 8, 15, 0, in: "UTC")))
    }

    // MARK: previews old/new ring times

    func testPreviewsBothRingTimesEachInItsOwnZone() throws {
        let prompt = try makePrompt(criticality: .standard)
        // Keep-anchor previews 07:00 Tokyo; follow-local previews 07:00 New York — the two differ, so the
        // user sees the old vs the new ring time.
        XCTAssertEqual(prompt.standingOption.resolution, .keepAnchorZone)
        XCTAssertEqual(prompt.standingOption.zone, try iana("Asia/Tokyo"))
        XCTAssertEqual(
            prompt.standingOption.nextRing, try makeDate(2026, 9, 1, 7, in: "Asia/Tokyo"))
        XCTAssertEqual(prompt.alternativeOption.resolution, .followDeviceZone)
        XCTAssertEqual(prompt.alternativeOption.zone, try iana("America/New_York"))
        XCTAssertEqual(
            prompt.alternativeOption.nextRing, try makeDate(2026, 9, 1, 7, in: "America/New_York"))
        XCTAssertNotEqual(prompt.standingOption.nextRing, prompt.alternativeOption.nextRing)
    }

    func testPreviewShowsNoRingWhenTheOnlyOccurrenceIsPast() throws {
        // A one-time alarm whose occurrence is already past → nil under both options (UI shows "won't
        // ring", never a wrong time).
        let prompt = try XCTUnwrap(
            builder.makePrompt(
                for: try alarm(year: 2026, month: 1, day: 1, criticality: .standard),
                decision: try askDecision(),
                zoneChange: try tokyoToNewYork(), now: try makeDate(2026, 8, 15, 0, in: "UTC")))
        XCTAssertNil(prompt.standingOption.nextRing)
        XCTAssertNil(prompt.alternativeOption.nextRing)
    }

    // MARK: no response preserves the documented default (#7)

    func testNoResponseKeepsTheDocumentedDefault() throws {
        let prompt = try makePrompt(criticality: .critical)
        XCTAssertEqual(prompt.noResponseResolution, .keepAnchorZone)
        XCTAssertEqual(prompt.resolve(.noResponse), .keepAsDocumented(.keepAnchorZone))
    }

    // MARK: a critical change confirms (#6)

    func testCriticalFollowLocalNeedsConfirmationThenApplies() throws {
        let prompt = try makePrompt(criticality: .critical)
        XCTAssertTrue(prompt.alternativeRequiresConfirmation)
        // Unconfirmed → the critical alarm is NOT moved; it awaits confirmation (#6).
        XCTAssertEqual(prompt.resolve(.followLocal(confirmed: false)), .needsConfirmation)
        // Confirmed → the change applies.
        XCTAssertEqual(prompt.resolve(.followLocal(confirmed: true)), .apply(.followDeviceZone))
    }

    func testStandardFollowLocalAppliesWithoutConfirmation() throws {
        let prompt = try makePrompt(criticality: .standard)
        XCTAssertFalse(prompt.alternativeRequiresConfirmation)
        XCTAssertEqual(prompt.resolve(.followLocal(confirmed: false)), .apply(.followDeviceZone))
    }

    func testExplicitKeepAnchorAppliesForBothCriticalities() throws {
        // Keeping the anchor is never a change, so it never needs confirmation.
        XCTAssertEqual(
            try makePrompt(criticality: .critical).resolve(.keepAnchor), .apply(.keepAnchorZone))
        XCTAssertEqual(
            try makePrompt(criticality: .standard).resolve(.keepAnchor), .apply(.keepAnchorZone))
    }

    func testNoResponseFailsClosedToAnchorEvenIfTheDecisionDefaultsToFollowLocal() throws {
        // Defense in depth (#7/#16): even a hostile/future decision whose standing slot is follow-local
        // must NOT re-anchor a critical alarm on no response — WG-105 pins the anchor default itself.
        let hostile = TravelPolicyDecision(
            outcome: .prompt(standing: .followDeviceZone, alternative: .keepAnchorZone),
            explanation: "hostile", evidence: [])
        let prompt = try XCTUnwrap(
            builder.makePrompt(
                for: try alarm(year: 2026, month: 9, day: 1, criticality: .critical),
                decision: hostile, zoneChange: try tokyoToNewYork(),
                now: try makeDate(2026, 8, 15, 0, in: "UTC")))
        XCTAssertEqual(prompt.standingOption.resolution, .keepAnchorZone)
        XCTAssertEqual(prompt.resolve(.noResponse), .keepAsDocumented(.keepAnchorZone))
    }

    func testWeeklyCriticalFollowLocalStillNeedsConfirmation() throws {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0), timeZone: try iana("Asia/Tokyo")))
        let stamp = try makeDate(2020, 1, 1, 0, in: "UTC")
        let weekly = try Alarm(
            id: AlarmID(try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))),
            label: "Wake", schedule: schedule, travelBehavior: .askOnChange, criticality: .critical,
            createdAt: stamp, updatedAt: stamp)
        let prompt = try XCTUnwrap(
            builder.makePrompt(
                for: weekly, decision: try askDecision(), zoneChange: try tokyoToNewYork(),
                now: try makeDate(2026, 8, 15, 0, in: "UTC")))
        XCTAssertNotNil(prompt.alternativeOption.nextRing)  // a weekly alarm always has a next ring
        XCTAssertEqual(prompt.resolve(.followLocal(confirmed: false)), .needsConfirmation)
    }

    // MARK: a deterministic policy surfaces no prompt

    func testDeterministicDecisionProducesNoPrompt() throws {
        let resolved = evaluator.evaluate(
            travel: TravelContext(
                zoneChange: try tokyoToNewYork(),
                detectedAt: try makeDate(2026, 8, 15, 0, in: "UTC"),
                location: nil),
            behavior: .followLocal, anchorZone: try iana("Asia/Tokyo"))
        XCTAssertNil(
            builder.makePrompt(
                for: try alarm(year: 2026, month: 9, day: 1, criticality: .standard),
                decision: resolved,
                zoneChange: try tokyoToNewYork(), now: try makeDate(2026, 8, 15, 0, in: "UTC")))
    }
}
