import Foundation
import XCTest

@testable import WakeGuard

/// WG-167: the Tomorrow Agent context builder. Verifies the context is built from **minimized structured
/// factors** (times + coarse bands, each with a stable ID), that **sensitive raw text is excluded** (a
/// factor value is a bare time, never a title), and that **missing permissions are represented** as
/// unavailable sources rather than silently dropped.
final class TomorrowContextBuilderTests: XCTestCase {

    private let builder = TomorrowContextBuilder()
    private let zoneID = "America/New_York"

    private func zone() throws -> TimeZone { try XCTUnwrap(TimeZone(identifier: zoneID)) }

    private func date(hour: Int, minute: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try zone()
        return try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 8, day: 11, hour: hour, minute: minute)))
    }

    private func readiness(_ contribution: Double) -> ReadinessAssessment {
        ReadinessAssessment(
            factors: [ReadinessFactor(kind: .sleepDuration, contribution: contribution, weight: 1)],
            certainty: .moderate)
    }

    private func debt(hours: Double) -> SleepDebtEstimate {
        SleepDebtEstimate(
            debt: hours * 3_600, sleepNeed: 8 * 3_600, nightsCounted: 5, nightsMissing: 0,
            wasCapped: false)
    }

    // MARK: full context from granted sources

    func testBuildsMinimizedFactorsWhenAllGranted() throws {
        let event = RedactedEventSummary(
            start: try date(hour: 9, minute: 0), end: try date(hour: 10, minute: 0),
            isAllDay: false, hasLocation: true, isConfirmedImportant: false)
        let plan = LatestSafeWakePlan(
            latestSafeWake: try date(hour: 6, minute: 45),
            bindingEventStart: try date(hour: 9, minute: 0),
            drivenByConfirmedImportant: false, appliedLeadTime: 2 * 3_600, bindingHasLocation: true,
            confidence: .high, consideredEventCount: 1, hasConflicts: false)
        let inputs = TomorrowContextInputs(
            earliestEvent: event, latestSafeWake: plan, sleepDebt: debt(hours: 2),
            readiness: readiness(0.9), calendarAccess: .granted, healthAccess: .granted)

        let context = builder.build(inputs, timeZone: try zone())

        XCTAssertEqual(context.value(for: .earliestObligation), "09:00")
        XCTAssertEqual(context.value(for: .latestSafeWake), "06:45")
        XCTAssertEqual(context.value(for: .readiness), "good")
        XCTAssertEqual(context.value(for: .sleepDebt), "moderate")
        XCTAssertTrue(context.unavailableSources.isEmpty)
    }

    // MARK: sensitive raw text is excluded

    func testFactorValuesAreTimesOrBandsNeverText() throws {
        let event = RedactedEventSummary(
            start: try date(hour: 7, minute: 5), end: try date(hour: 8, minute: 0), isAllDay: false,
            hasLocation: false, isConfirmedImportant: false)
        let context = builder.build(
            TomorrowContextInputs(earliestEvent: event, calendarAccess: .granted),
            timeZone: try zone())

        // The earliest-obligation factor is a bare clock time — no letters, so no title/text can leak.
        let value = try XCTUnwrap(context.value(for: .earliestObligation))
        XCTAssertEqual(value, "07:05")
        XCTAssertNil(
            value.rangeOfCharacter(from: .letters), "a factor value must never contain text")
    }

    // MARK: missing permissions are represented

    func testDeniedCalendarIsRepresentedNotDropped() throws {
        let context = builder.build(
            TomorrowContextInputs(calendarAccess: .denied, healthAccess: .granted),
            timeZone: try zone())
        XCTAssertTrue(context.unavailableSources.contains(.calendar))
        XCTAssertNil(context.value(for: .earliestObligation))
    }

    func testDeniedHealthIsRepresentedNotDropped() throws {
        let context = builder.build(
            TomorrowContextInputs(
                readiness: readiness(0.9), calendarAccess: .granted, healthAccess: .denied),
            timeZone: try zone())
        XCTAssertTrue(context.unavailableSources.contains(.health))
        XCTAssertNil(context.value(for: .readiness))
    }

    func testNotDeterminedSourcesAreBothUnavailable() throws {
        let context = builder.build(TomorrowContextInputs(), timeZone: try zone())
        XCTAssertEqual(Set(context.unavailableSources), [.calendar, .health])
        XCTAssertTrue(context.factors.isEmpty)
    }

    // MARK: coarse sleep-debt banding (never the raw value)

    func testSleepDebtBands() throws {
        let cases: [(Double, String)] = [(0, "none"), (1, "mild"), (2, "moderate"), (4, "high")]
        for (hours, band) in cases {
            let context = builder.build(
                TomorrowContextInputs(sleepDebt: debt(hours: hours), healthAccess: .granted),
                timeZone: try zone())
            XCTAssertEqual(context.value(for: .sleepDebt), band, "\(hours)h should band to \(band)")
        }
    }

    // MARK: partial health access still yields factors

    func testPartialHealthAccessStillProducesFactors() throws {
        let context = builder.build(
            TomorrowContextInputs(readiness: readiness(0.3), healthAccess: .partial),
            timeZone: try zone())
        XCTAssertEqual(context.value(for: .readiness), "low")
        XCTAssertFalse(context.unavailableSources.contains(.health))
    }
}
