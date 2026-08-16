import Foundation
import XCTest

@testable import WakeGuard

/// WG-310: the motion-based overnight-disturbance estimate (the fallback "interrupted sleep" signal for
/// users without Apple sleep tracking). Verifies the estimator **counts distinct movement episodes** and
/// **totals moving time** within the window, that **`.unknown`/`.stationary` are not disturbances**
/// (conservative under-counting), that **no motion data → unavailable (`nil`)** while a still night is the
/// distinct `.none`, and that spans are **clipped to the window** (last segment ends at the window edge).
final class SleepDisturbanceEstimatorTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private var window: DateInterval {
        DateInterval(start: base, end: base.addingTimeInterval(3_600))
    }

    private func sample(_ offset: Double, _ kind: MotionActivityKind) -> MotionActivitySample {
        MotionActivitySample(timestamp: base.addingTimeInterval(offset), quality: .high, kind: kind)
    }

    func testStillNightRecordsNoneNotUnavailable() {
        let samples = [sample(0, .stationary), sample(1_800, .stationary)]
        XCTAssertEqual(
            SleepDisturbanceEstimator.estimate(samples: samples, window: window),
            SleepDisturbances.none,
            "a still night is recorded as zero pickups, distinct from unavailable")
    }

    func testOnePickupCountsTheMovingSpan() {
        // stationary, a 5-minute walk at 10:00, stationary again.
        let samples = [sample(0, .stationary), sample(600, .walking), sample(900, .stationary)]
        XCTAssertEqual(
            SleepDisturbanceEstimator.estimate(samples: samples, window: window),
            SleepDisturbances(pickups: 1, movingDuration: 300))
    }

    func testConsecutiveMovingSamplesAreOneEpisode() {
        let samples = [
            sample(0, .stationary), sample(600, .walking), sample(720, .running),
            sample(900, .stationary),
        ]
        let result = SleepDisturbanceEstimator.estimate(samples: samples, window: window)
        XCTAssertEqual(result?.pickups, 1, "a continuous moving run is one disturbance, not two")
        XCTAssertEqual(result?.movingDuration, 300)
    }

    func testSeparateMovingRunsCountAsSeparatePickups() {
        let samples = [
            sample(0, .stationary), sample(600, .walking), sample(900, .stationary),
            sample(1_800, .automotive), sample(2_100, .stationary),
        ]
        XCTAssertEqual(
            SleepDisturbanceEstimator.estimate(samples: samples, window: window)?.pickups, 2)
    }

    func testUnknownAndStationaryAreNotDisturbances() {
        let samples = [sample(0, .stationary), sample(600, .unknown), sample(1_200, .stationary)]
        XCTAssertEqual(
            SleepDisturbanceEstimator.estimate(samples: samples, window: window),
            SleepDisturbances.none,
            "an unconfident classification never counts as a disturbance (under-count, not over)")
    }

    func testMovingSpanIsClippedToTheWindowEnd() {
        // A walk starting near the end runs only to the window edge, not beyond.
        let samples = [sample(0, .stationary), sample(3_000, .walking)]
        XCTAssertEqual(
            SleepDisturbanceEstimator.estimate(samples: samples, window: window),
            SleepDisturbances(pickups: 1, movingDuration: 600))
    }

    func testNoMotionDataIsUnavailable() {
        XCTAssertNil(
            SleepDisturbanceEstimator.estimate(samples: [], window: window), "no data → unavailable"
        )
        // A sample entirely after the window contributes no in-window span → still unavailable.
        XCTAssertNil(
            SleepDisturbanceEstimator.estimate(samples: [sample(5_000, .walking)], window: window))
    }

    func testOvernightWindowEndsAtNowAndLooksBackByLookback() {
        let now = base
        let derived = SleepDisturbanceEstimator.overnightWindow(endingAt: now, lookback: 8 * 3_600)
        XCTAssertEqual(derived.end, now)
        XCTAssertEqual(derived.start, now.addingTimeInterval(-8 * 3_600))
    }
}
