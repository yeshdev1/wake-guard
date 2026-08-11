import Foundation
import XCTest

@testable import WakeGuard

/// WG-222: cold-launch & reconciliation performance. Records the next-occurrence **hot-path** baseline
/// (`measure`), asserts a **large alarm history** reconciles within a CI-safe bound (so a big history can't
/// make launch pathological), and checks the **budget is documented** (`docs/PERFORMANCE.md`).
final class PerformanceTests: XCTestCase {

    private let engine = AlarmSchedulingEngine()

    private func timeZone() throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    }

    private func rule(minute: Int) throws -> ScheduleRule {
        .weekly(
            WeeklySchedule(
                days: try WeekdaySet([.monday, .wednesday, .friday]),
                time: try TimeOfDay(hour: 6, minute: minute % 60),
                timeZone: try IANATimeZone(identifier: "America/New_York")))
    }

    private func now() throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try timeZone()
        return try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 5)))
    }

    /// Hot-path baseline: computing the next occurrence per alarm during reconciliation.
    func testNextOccurrenceHotPathBaseline() throws {
        let rule = try rule(minute: 30)
        let zone = try timeZone()
        let start = try now()
        measure {
            for _ in 0..<10_000 { _ = engine.nextOccurrence(of: rule, after: start, in: zone) }
        }
    }

    /// A functional per-call lock for the hot path. The `measure` baseline above records but does not gate
    /// (no `.xcbaseline` is checked in), so a gross per-call regression — an accidental O(n) scan in the
    /// DST/Calendar path, say — would still pass. This bounds 10,000 computations by wall clock so such a
    /// regression fails CI independently of Xcode baselines (WG-249).
    func testNextOccurrenceHotPathStaysWithinAFunctionalBound() throws {
        let rule = try rule(minute: 30)
        let zone = try timeZone()
        let start = try now()
        let elapsed = ContinuousClock().measure {
            for _ in 0..<10_000 { _ = engine.nextOccurrence(of: rule, after: start, in: zone) }
        }
        // Generous CI-safe bound (observed cost is well under this); the on-device budget is far tighter.
        XCTAssertLessThan(
            elapsed, .seconds(2), "10,000 next-occurrence calls should be well under budget")
    }

    /// A large alarm history must reconcile within a bound — cost is linear in alarm count.
    func testLargeAlarmHistoryReconcilesWithinBudget() throws {
        let zone = try timeZone()
        let start = try now()
        let rules = try (0..<2_000).map { try rule(minute: $0) }

        let elapsed = ContinuousClock().measure {
            for rule in rules { _ = engine.nextOccurrence(of: rule, after: start, in: zone) }
        }
        // Generous CI-safe bound; the documented budget is far tighter on-device.
        XCTAssertLessThan(
            elapsed, .seconds(2), "reconciling 2,000 alarms should be well under budget")
    }

    func testPerformanceBudgetIsDocumented() throws {
        let doc = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("docs/PERFORMANCE.md"), encoding: .utf8)
        for required in ["Cold launch", "reconciliation", "Budget", "baseline"] {
            XCTAssertTrue(
                doc.lowercased().contains(required.lowercased()), "budget doc missing '\(required)'"
            )
        }
    }
}
