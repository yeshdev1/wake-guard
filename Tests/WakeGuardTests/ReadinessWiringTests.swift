import Foundation
import XCTest

@testable import WakeGuard

/// WG-131 composition (wiring E2): the readiness card is driven by a real sleep source composed in the
/// graph, and degrades **safely** with no data — an unavailable "not enough data" assessment, never a
/// fabricated score (#36/#38). Health is optional; this is the path the simulator / an ineligible device
/// takes.
@MainActor
final class ReadinessWiringTests: XCTestCase {

    func testGraphSleepQueryDrivesReadinessThatDegradesSafely() async throws {
        let env = try AppEnvironment.inMemory()
        let model = ReadinessViewModel(sleepQuery: env.sleepQuery)

        await model.refresh(now: Date(timeIntervalSince1970: 1_700_000_000))

        let assessment = try XCTUnwrap(model.assessment, "readiness computes even with no data")
        XCTAssertNil(
            assessment.weightedScore,
            "no sleep data → unavailable readiness, never a fabricated score (#36/#38)")
        XCTAssertTrue(assessment.factors.isEmpty, "no factors when there's no data")
    }

    /// WG-318: the in-memory graph is what SwiftUI previews **and** the `-uiTesting` screenshot tour run
    /// against, so whatever it renders *is* the section's documented appearance. It injected a source that
    /// threw `.unavailable(.notPresent)`, so every preview — and the committed `11-readiness-degraded`
    /// reference screenshot — showed "This device can't track movement": a claim about the reader's hardware,
    /// made by a double whose only property is having no data.
    ///
    /// The second cost is the one no reviewer had to argue for: with the graph's source *always* throwing,
    /// the section's **primary** rendering — an actual estimate — was never exercised by anything, in any
    /// test, at any layer. A double that can only fail can only document failure.
    ///
    /// Values are pinned, not merely unwrapped: `SleepDisturbances.none` and a zero rest window would satisfy
    /// a presence check while proving the fixture resolves no night at all.
    func testTheGraphMotionSourceRendersARealEstimateRatherThanAHardwareClaim() async throws {
        let env = try AppEnvironment.inMemory()
        // The calendar is injected with a fixed zone rather than mutating `NSTimeZone.default`: the night
        // anchor is local-wall-clock, so the candidate span's length — and therefore whether the fixture is
        // clipped — would otherwise depend on the machine running the suite.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let model = ReadinessViewModel(
            sleepQuery: env.sleepQuery, motionHistory: env.motionActivityHistory, calendar: calendar
        )

        // 2023-11-14 22:13:20Z → a candidate span of [11-13 18:00Z, now], comfortably longer than the night.
        await model.refresh(now: Date(timeIntervalSince1970: 1_700_000_000))

        guard case .available(let disturbances, let rest) = model.movement else {
            return XCTFail(
                """
                previews and the screenshot tour render \(model.movement); the graph's motion source must \
                produce a night so the section's real appearance is what gets documented
                """)
        }
        XCTAssertEqual(disturbances.pickups, 1, "the fixture night holds exactly one disturbance")
        XCTAssertEqual(disturbances.movingDuration, 300, accuracy: 1, "a five-minute disturbance")
        XCTAssertEqual(rest, 5.5 * 3600, accuracy: 1, "the longest quiet stretch is 5h30m")
    }

    /// One `now` is not the input shape. The candidate span runs from the **previous local 18:00**, so its
    /// length swings between ~6h (screen opened at local midnight) and ~30h (opened late evening), and the
    /// screenshot tour runs at whatever time CI happens to start. A fixture tuned to one hour would document
    /// the section correctly in the test above and render "not enough movement data" in the artefact.
    ///
    /// This is also the only test that can see the clamp collision: below ~8h two script entries land on
    /// `window.start`, and `sorted(by:)` being unstable meant the span after it could classify as moving —
    /// dissolving the night at some hours and not others.
    func testTheGraphMotionSourceResolvesANightAtEveryHourOfTheDay() async throws {
        let env = try AppEnvironment.inMemory()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let midnight = Date(timeIntervalSince1970: 1_699_920_000)  // 2023-11-14 00:00:00Z

        for hour in 0..<24 {
            let model = ReadinessViewModel(
                sleepQuery: env.sleepQuery, motionHistory: env.motionActivityHistory,
                calendar: calendar)

            await model.refresh(now: midnight.addingTimeInterval(Double(hour) * 3600))

            guard case .available(let disturbances, let rest) = model.movement else {
                XCTFail("at \(hour):00 the section renders \(model.movement), not an estimate")
                continue
            }
            XCTAssertEqual(
                disturbances.pickups, 1,
                "at \(hour):00 the scripted single disturbance is not reported exactly once")
            XCTAssertGreaterThanOrEqual(
                rest, SleepDisturbanceEstimator.minimumNightDuration,
                "at \(hour):00 the rest window is shorter than the night it came from")
        }
    }
}
