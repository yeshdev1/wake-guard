import XCTest

@testable import WakeGuard

/// WG-070: the anti-shake / anti-replay cadence defense. Verifies that a plausibly-paced, naturally
/// varied gait corroborates a walk, that rapid/erratic/out-of-band/metronomic cadence does not, that
/// reconstructing intervals from cumulative steps drops duplicate and reset samples (so replays can't
/// inflate), and — end to end — that a real walking stream passes while a bursty shake stream fails.
final class CadenceRegularityTests: XCTestCase {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func obs(_ offset: TimeInterval, steps: Int) -> MovementObservation {
        MovementObservation(
            timestamp: Self.base.addingTimeInterval(offset), isMoving: true, cumulativeSteps: steps,
            source: .pedometer)
    }

    // MARK: - classify()

    func testPlausibleGaitCorroborates() {
        let intervals = [0.45, 0.55, 0.5, 0.6, 0.48, 0.52, 0.47, 0.58]
        let verdict = CadenceRegularity.classify(intervals: intervals)
        XCTAssertEqual(verdict, .plausibleGait)
        XCTAssertTrue(verdict.corroboratesWalk)
    }

    func testErraticCadenceIsTooErratic() {
        // In-band per-step timing, but wildly alternating — a shake, not a gait (CV > 0.5).
        let intervals = [0.3, 1.1, 0.3, 1.1, 0.3, 1.1, 0.3, 1.1]
        XCTAssertEqual(CadenceRegularity.classify(intervals: intervals), .tooErratic)
    }

    func testImplausiblyFastTimingFails() {
        let intervals = [0.1, 0.12, 0.11, 0.1, 0.13, 0.11, 0.1, 0.12]  // ~10 steps/s — a shake
        XCTAssertEqual(CadenceRegularity.classify(intervals: intervals), .implausibleTiming)
    }

    func testImplausiblySlowTimingFails() {
        let intervals = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 1.5]  // a 1.5 s gap — not continuous
        XCTAssertEqual(CadenceRegularity.classify(intervals: intervals), .implausibleTiming)
    }

    func testMetronomicCadenceIsTooRegular() {
        // Perfectly identical intervals — a tap or a replayed loop; a human gait never does this.
        let intervals = Array(repeating: 0.5, count: 8)
        XCTAssertEqual(CadenceRegularity.classify(intervals: intervals), .tooRegular)
    }

    func testPacedShakePassesAsKnownLimitation() {
        // HONEST LIMITATION (WG-070 review S1): a *regular* ~2/s shake with hand jitter lands inside
        // the plausible CV band — a CV-only model can't tell it from a gait. Rapid *irregular* motion
        // IS caught (see the erratic / implausible-timing tests); the regular-shake residual is
        // deferred to WG-075 calibration, and safety still holds because a pass requires multiple
        // independent signals (#19) and this verdict is corroboration only, never a standalone pass.
        // This test pins the hole so it cannot change silently.
        let pacedShake = [0.50, 0.46, 0.53, 0.48, 0.55, 0.44, 0.51, 0.49, 0.52, 0.47]
        XCTAssertEqual(CadenceRegularity.classify(intervals: pacedShake), .plausibleGait)
    }

    func testTooFewIntervalsFails() {
        XCTAssertEqual(CadenceRegularity.classify(intervals: [0.5, 0.5, 0.5]), .tooFewSteps)
    }

    func testNonFiniteIntervalsAreDropped() {
        // The .nan / 0 / negative are filtered, leaving too few → not a spurious pass.
        let intervals = [0.5, .nan, 0.5, -1, 0.5, 0]
        XCTAssertEqual(CadenceRegularity.classify(intervals: intervals), .tooFewSteps)
    }

    func testOnlyPlausibleGaitCorroborates() {
        for verdict in CadenceVerdict.allCases {
            XCTAssertEqual(verdict.corroboratesWalk, verdict == .plausibleGait, "\(verdict)")
        }
    }

    // MARK: - intervals(): duplicates & resets can't inflate

    func testReconstructionSkipsDuplicateSamples() {
        // A repeated cumulative count (a replayed/duplicate sample) adds no interval.
        let samples = [obs(0, steps: 0), obs(1, steps: 4), obs(1.5, steps: 4), obs(2, steps: 8)]
        let intervals = CadenceRegularity.intervals(from: samples)
        XCTAssertEqual(intervals.count, 2, "the duplicate-step sample contributed no interval")
        XCTAssertEqual(intervals[0], 0.25, accuracy: 1e-9)
        XCTAssertEqual(intervals[1], 0.125, accuracy: 1e-9)
    }

    func testReconstructionSkipsResets() {
        let samples = [obs(0, steps: 100), obs(1, steps: 104), obs(2, steps: 3), obs(3, steps: 7)]
        let intervals = CadenceRegularity.intervals(from: samples)
        XCTAssertEqual(intervals, [0.25, 0.25], "a counter reset contributes no interval")
    }

    func testDuplicatePaddingCannotManufactureCadence() {
        // Two real step segments padded with 20 duplicate samples still yields only 2 intervals →
        // never enough to pass (duplicate samples cannot inflate progress).
        var samples = [obs(0, steps: 0), obs(1, steps: 4), obs(2, steps: 8)]
        // 20 duplicate samples (no new steps) appended.
        samples += (0..<20).map { obs(2.0 + Double($0) * 0.01, steps: 8) }
        XCTAssertEqual(CadenceRegularity.verify(samples), .tooFewSteps)
    }

    // MARK: - verify(): end to end

    func testRealWalkStreamCorroborates() {
        // ~2 steps/s with natural pace variation over 9 s.
        let counts = [0, 2, 4, 7, 9, 11, 14, 16, 18, 20]
        let samples = counts.enumerated().map { obs(Double($0.offset), steps: $0.element) }
        XCTAssertEqual(CadenceRegularity.verify(samples), .plausibleGait)
    }

    func testBurstyShakeStreamFails() {
        // A shake makes CMPedometer emit steps in bursts — implausibly fast within-burst timing.
        let counts = [0, 5, 6, 12, 13, 20, 21, 28, 29, 35]
        let samples = counts.enumerated().map { obs(Double($0.offset), steps: $0.element) }
        XCTAssertFalse(
            CadenceRegularity.verify(samples).corroboratesWalk, "a bursty shake is not a gait")
    }

    func testNoStepsDoesNotCorroborate() {
        let stationary = (0..<10).map { obs(Double($0), steps: 5) }  // no new steps
        XCTAssertEqual(CadenceRegularity.verify(stationary), .tooFewSteps)
    }
}
