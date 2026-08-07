import XCTest

@testable import WakeGuard

/// WG-069: the ten-second walking verification. A validated walking episode passes; a short
/// movement, a stationary (stepless) pickup, and a sparse injected episode each fail one of the
/// three gates; and the thresholds are configurable only *within safe bounds* — a lenient config is
/// clamped so the ten-second floor (and step/density floors) always hold.
final class WalkVerificationTests: XCTestCase {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func episode(duration: TimeInterval, steps: Int, observations: Int) -> MovementEpisode {
        MovementEpisode(
            start: Self.base, end: Self.base.addingTimeInterval(duration), stepCount: steps,
            observationCount: observations)
    }

    private let verifier = WalkVerifier()

    // MARK: - Pass / fail

    func testValidatedWalkPasses() {
        // 12 s, 20 steps, dense (mean gap 1 s).
        let walk = episode(duration: 12, steps: 20, observations: 13)
        XCTAssertTrue(verifier.isValidWalk(walk))
        XCTAssertEqual(verifier.verify([walk]), .passed)
    }

    func testShortMovementDoesNotPass() {
        // Dense and enough steps, but only 5 s — below the ten-second floor.
        let short = episode(duration: 5, steps: 20, observations: 6)
        XCTAssertFalse(verifier.isValidWalk(short))
        XCTAssertEqual(verifier.verify([short]), .insufficient)
    }

    func testStationaryPickupDoesNotPass() {
        // Long and dense, but almost no real steps — a device-only pickup, not a walk.
        let pickup = episode(duration: 12, steps: 3, observations: 13)
        XCTAssertEqual(verifier.verify([pickup]), .insufficient)
        // And no episode at all (a pickup forms no movement episode) is likewise not a pass.
        XCTAssertEqual(verifier.verify([]), .insufficient)
    }

    func testSparseEpisodeDoesNotPass() {
        // Long enough with enough steps, but only 5 observations over 12 s (mean gap 3 s > 2 s) — a
        // sparse injected/replayed stream, not a real dense walk.
        let sparse = episode(duration: 12, steps: 20, observations: 5)
        XCTAssertFalse(verifier.isValidWalk(sparse))
        XCTAssertEqual(verifier.verify([sparse]), .insufficient)
    }

    func testSingleObservationEpisodeDoesNotPass() {
        XCTAssertFalse(verifier.isValidWalk(episode(duration: 12, steps: 20, observations: 1)))
    }

    func testNonFiniteDurationCannotPass() {
        let corrupt = MovementEpisode(
            start: Self.base, end: Date(timeIntervalSince1970: .nan), stepCount: 50,
            observationCount: 20)
        XCTAssertFalse(verifier.isValidWalk(corrupt), "a non-finite duration fails closed")
        XCTAssertEqual(verifier.verify([corrupt]), .insufficient)
    }

    func testNegativeDurationCannotPass() {
        let backwards = MovementEpisode(
            start: Self.base.addingTimeInterval(10), end: Self.base, stepCount: 50,
            observationCount: 20)
        XCTAssertFalse(
            verifier.isValidWalk(backwards), "a negative (end<start) duration fails closed")
    }

    func testPassesIfAnyEpisodeQualifies() {
        let episodes = [
            episode(duration: 4, steps: 20, observations: 5),  // too short
            episode(duration: 12, steps: 20, observations: 13),  // valid walk
        ]
        XCTAssertEqual(verifier.verify(episodes), .passed)
    }

    // MARK: - Thresholds configurable within safe bounds

    func testDefaultRequirementsAreTheSafeFloor() {
        let requirements = WalkRequirements()
        XCTAssertEqual(requirements.minimumDuration, 10)
        XCTAssertEqual(requirements.minimumSteps, 10)
        XCTAssertEqual(requirements.maximumMeanGap, 2.0)
    }

    func testLenientThresholdsAreClampedToSafeBounds() {
        let requirements = WalkRequirements(
            minimumDuration: 2, minimumSteps: 1, maximumMeanGap: 100)
        XCTAssertEqual(requirements.minimumDuration, 10, "cannot drop below the ten-second floor")
        XCTAssertEqual(requirements.minimumSteps, 10, "cannot require fewer than the step floor")
        XCTAssertEqual(
            requirements.maximumMeanGap, 2.0, "cannot accept a sparser stream than the bar")
    }

    func testStricterThresholdsAreAllowed() {
        let requirements = WalkRequirements(
            minimumDuration: 30, minimumSteps: 50, maximumMeanGap: 0.5)
        XCTAssertEqual(requirements.minimumDuration, 30)
        XCTAssertEqual(requirements.minimumSteps, 50)
        XCTAssertEqual(requirements.maximumMeanGap, 0.5)
    }

    func testThresholdsClampedToCeilings() {
        let requirements = WalkRequirements(
            minimumDuration: 500, minimumSteps: 999, maximumMeanGap: 0.01)
        XCTAssertEqual(requirements.minimumDuration, 120)
        XCTAssertEqual(requirements.minimumSteps, 200)
        XCTAssertEqual(requirements.maximumMeanGap, 0.2, "clamped up to the strictest sane density")
    }

    func testNonFiniteThresholdsFallToSafeDefaults() {
        let requirements = WalkRequirements(minimumDuration: .nan, maximumMeanGap: .infinity)
        XCTAssertEqual(
            requirements.minimumDuration, 10, "a non-finite duration falls to the ten-second floor")
        XCTAssertEqual(
            requirements.maximumMeanGap, 2.0,
            "an infinite gap falls to the safe bar, never infinitely lenient")
        let nanGap = WalkRequirements(maximumMeanGap: .nan)
        XCTAssertEqual(nanGap.maximumMeanGap, 2.0, "a non-finite gap falls to the safe default")
    }

    func testClampEnforcesTenSecondFloorEvenWithLenientConfig() {
        // Even asked for a 1-second challenge, a 5-second "walk" must not pass — the clamp holds.
        let lenient = WalkVerifier(requirements: WalkRequirements(minimumDuration: 1))
        let fiveSeconds = episode(duration: 5, steps: 20, observations: 6)
        XCTAssertEqual(lenient.verify([fiveSeconds]), .insufficient)
    }
}
