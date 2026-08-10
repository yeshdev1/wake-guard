import Foundation
import XCTest

@testable import WakeGuard

/// WG-145: the latest-safe-wake calculator. Verifies the calculation is **pure and transparent**
/// (`latestSafeWake == bindingStart − leadTime`), that **all-day and conflicting events are handled**, and
/// that **results include uncertainty** (a user-confirmed event → high; an inferred one → moderate;
/// conflicts lower it a step).
final class LatestSafeWakeCalculatorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let minute: TimeInterval = 60
    private let profile = MorningPreparationProfile.default  // 45 / 30 / 10 min

    private func event(
        startMin: Double, durationMin: Double = 60, allDay: Bool = false, location: Bool = false,
        important: Bool = false
    ) -> RedactedEventSummary {
        let start = now.addingTimeInterval(startMin * minute)
        return RedactedEventSummary(
            start: start, end: start.addingTimeInterval(durationMin * minute), isAllDay: allDay,
            hasLocation: location, isConfirmedImportant: important)
    }

    private func plan(_ events: [RedactedEventSummary]) -> LatestSafeWakePlan? {
        LatestSafeWakeCalculator.plan(for: events, profile: profile, after: now)
    }

    // MARK: pure + transparent

    func testWakeIsTransparentlyTheBindingStartMinusLeadTime() throws {
        // A critical event 3h out, no location → lead = prep(45) + safety(10) = 55 min.
        let plan = try XCTUnwrap(plan([event(startMin: 180, important: true)]))
        XCTAssertEqual(plan.appliedLeadTime, (45 + 10) * minute)
        XCTAssertEqual(plan.latestSafeWake, now.addingTimeInterval((180 - 55) * minute))
        XCTAssertEqual(
            plan.latestSafeWake, plan.bindingEventStart.addingTimeInterval(-plan.appliedLeadTime),
            "recomputable: wake == start − leadTime")
        XCTAssertTrue(plan.drivenByConfirmedImportant)
        XCTAssertEqual(plan.confidence, .high)
    }

    func testALocationAddsTheTravelBuffer() throws {
        let withLocation = try XCTUnwrap(
            plan([event(startMin: 180, location: true, important: true)]))
        XCTAssertEqual(
            withLocation.appliedLeadTime, (45 + 30 + 10) * minute, "prep + travel + safety")
    }

    // MARK: all-day + no-timed handling

    func testAllDayEventsAreExcluded() throws {
        // An all-day event alongside a timed one → the timed one drives the plan.
        let plan = try XCTUnwrap(
            plan([event(startMin: 200, allDay: true), event(startMin: 180, important: true)]))
        XCTAssertEqual(plan.consideredEventCount, 1)
        XCTAssertEqual(plan.bindingEventStart, now.addingTimeInterval(180 * minute))
    }

    func testNoTimedEventIsUnavailable() {
        XCTAssertNil(plan([]), "no events → unavailable")
        XCTAssertNil(plan([event(startMin: 100, allDay: true)]), "only all-day → unavailable")
        XCTAssertNil(
            plan([event(startMin: -60, important: true)]), "only a past event → unavailable")
    }

    // MARK: earliest deadline wins

    func testTheEarliestDeadlineBinds() throws {
        // Two critical events; the earlier one's ready-by is the binding wake time.
        let plan = try XCTUnwrap(
            plan([event(startMin: 300, important: true), event(startMin: 120, important: true)]))
        XCTAssertEqual(plan.bindingEventStart, now.addingTimeInterval(120 * minute))
        XCTAssertEqual(plan.latestSafeWake, now.addingTimeInterval((120 - 55) * minute))
    }

    // MARK: uncertainty

    func testInferredFirstEventGivesModerateConfidence() throws {
        // No confirmed-important event → the earliest timed event is an inferred (moderate) deadline.
        let plan = try XCTUnwrap(plan([event(startMin: 180), event(startMin: 300)]))
        XCTAssertFalse(plan.drivenByConfirmedImportant)
        XCTAssertEqual(plan.confidence, .moderate)
        XCTAssertEqual(plan.bindingEventStart, now.addingTimeInterval(180 * minute))
    }

    func testConflictingEventsAreHandledAndLowerConfidence() throws {
        // Two overlapping events (09:00–10:00 and 09:30–10:30).
        let overlapping = [
            event(startMin: 180, durationMin: 60, important: true),
            event(startMin: 210, durationMin: 60, important: true),
        ]
        let plan = try XCTUnwrap(plan(overlapping))
        XCTAssertTrue(plan.hasConflicts)
        XCTAssertEqual(plan.confidence, .moderate, "critical(high) downgraded by a conflict")
    }

    func testInferredPlusConflictIsLowConfidence() throws {
        let overlapping = [
            event(startMin: 180, durationMin: 90), event(startMin: 210, durationMin: 60),
        ]
        let plan = try XCTUnwrap(plan(overlapping))
        XCTAssertTrue(plan.hasConflicts)
        XCTAssertEqual(plan.confidence, .low, "inferred(moderate) downgraded by a conflict")
    }

    func testNonOverlappingEventsHaveNoConflict() throws {
        let plan = try XCTUnwrap(
            plan([event(startMin: 180, durationMin: 30), event(startMin: 300, durationMin: 30)]))
        XCTAssertFalse(plan.hasConflicts)
    }
}
