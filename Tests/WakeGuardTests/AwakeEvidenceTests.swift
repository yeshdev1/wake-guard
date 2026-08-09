import XCTest

@testable import WakeGuard

/// WG-080: the deterministic awake-evidence model. Verifies it weighs the four factors (recent steps,
/// sustained episode, recency, optional device interaction), that **no single weak signal is
/// conclusive** (`.likely` needs corroboration), that the per-factor contributions are inspectable,
/// and that it derives from movement episodes (WG-067). The model is advisory — it produces an
/// assessment, never a suppression (#8).
final class AwakeEvidenceTests: XCTestCase {

    private func input(
        steps: Int = 0, duration: TimeInterval = 0, recency: TimeInterval = .infinity,
        device: Bool = false
    ) -> AwakeEvidenceInput {
        AwakeEvidenceInput(
            recentStepCount: steps, longestEpisodeDuration: duration,
            secondsSinceLastMovement: recency, deviceInteracted: device)
    }

    // MARK: - No single weak signal is conclusive

    func testNoSingleFactorIsConclusive() {
        XCTAssertNotEqual(AwakeEvidenceModel.evaluate(input(steps: 30)).likelihood, .likely)
        XCTAssertNotEqual(AwakeEvidenceModel.evaluate(input(duration: 40)).likelihood, .likely)
        XCTAssertNotEqual(AwakeEvidenceModel.evaluate(input(recency: 60)).likelihood, .likely)
        XCTAssertNotEqual(AwakeEvidenceModel.evaluate(input(device: true)).likelihood, .likely)
    }

    func testCorroborationReachesLikely() {
        let evidence = AwakeEvidenceModel.evaluate(input(steps: 30, duration: 40))
        XCTAssertEqual(evidence.likelihood, .likely)
        XCTAssertEqual(Set(evidence.presentFactors), [.recentSteps, .sustainedEpisode])
    }

    func testNoEvidenceIsNotEnough() {
        XCTAssertEqual(AwakeEvidenceModel.evaluate(input()).likelihood, .notEnough)
    }

    // MARK: - Inspectable contributions

    func testContributionsAreInspectable() {
        let evidence = AwakeEvidenceModel.evaluate(input(steps: 30))
        XCTAssertEqual(evidence.contributions.count, 4, "every factor is reported, present or not")
        let steps = evidence.contributions.first { $0.factor == .recentSteps }
        XCTAssertEqual(steps?.present, true)
        XCTAssertEqual(steps?.contribution, 0.4)
        XCTAssertEqual(
            evidence.contributions.first { $0.factor == .deviceInteraction }?.present, false)
        XCTAssertEqual(
            evidence.contributions.first { $0.factor == .deviceInteraction }?.contribution, 0)
    }

    // MARK: - Factor gates

    func testRecencyWindowGatesRecentMovement() {
        XCTAssertEqual(AwakeEvidenceModel.evaluate(input(recency: 100)).likelihood, .weak)
        XCTAssertEqual(AwakeEvidenceModel.evaluate(input(recency: 600)).likelihood, .notEnough)
    }

    // MARK: - Derive from movement episodes (WG-067)

    func testDeriveFromRecentEpisode() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let now = base.addingTimeInterval(30)
        let episode = MovementEpisode(
            start: base, end: base.addingTimeInterval(25), stepCount: 20, observationCount: 26)
        let evidence = AwakeEvidenceModel.evaluate(
            episodes: [episode], deviceInteracted: false, now: now)
        XCTAssertEqual(evidence.likelihood, .likely, "recent steps + sustained + recent movement")
        XCTAssertTrue(evidence.presentFactors.contains(.recentMovement))
    }

    func testStaleEpisodeDropsRecencyFactor() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let now = base.addingTimeInterval(1000)
        let episode = MovementEpisode(
            start: base, end: base.addingTimeInterval(25), stepCount: 20, observationCount: 26)
        let evidence = AwakeEvidenceModel.evaluate(
            episodes: [episode], deviceInteracted: false, now: now)
        XCTAssertFalse(
            evidence.presentFactors.contains(.recentMovement), "movement 16 min ago isn't recent")
        XCTAssertTrue(evidence.presentFactors.contains(.recentSteps))
        XCTAssertEqual(evidence.likelihood, .likely, "steps + sustained still corroborate")
    }

    // MARK: - No single factor is conclusive is STRUCTURAL, not a default-weights coincidence

    func testHostileConfigCannotMakeSingleFactorConclusive() {
        // Every weight is set at/above the likely bar; the Config initialiser must clamp each one
        // strictly below `likelyThreshold`, so a lone maxed factor still cannot reach `.likely`.
        let hostile = AwakeEvidenceModel.Config(
            minRecentSteps: 15, minSustainedDuration: 20, recencyWindow: 300,
            recentStepsWeight: 0.9, sustainedEpisodeWeight: 0.9, recentMovementWeight: 0.9,
            deviceInteractionWeight: 0.9, weakThreshold: 0.25, likelyThreshold: 0.6)
        XCTAssertNotEqual(
            AwakeEvidenceModel.evaluate(input(steps: 30), config: hostile).likelihood, .likely)
        XCTAssertNotEqual(
            AwakeEvidenceModel.evaluate(input(duration: 40), config: hostile).likelihood, .likely)
        XCTAssertNotEqual(
            AwakeEvidenceModel.evaluate(input(recency: 60), config: hostile).likelihood, .likely)
        XCTAssertNotEqual(
            AwakeEvidenceModel.evaluate(input(device: true), config: hostile).likelihood, .likely)
    }

    func testDevicePickupCannotTipSingleMainFactorToLikely() {
        // A bare pickup is supporting-only (0.15) — with one main factor it stays `.weak`, so a
        // device interaction is never the deciding vote into `.likely`.
        let evidence = AwakeEvidenceModel.evaluate(input(steps: 30, device: true))
        XCTAssertEqual(evidence.likelihood, .weak)
    }

    // MARK: - Fail-closed on adversarial numeric inputs (raw overload)

    func testNonFiniteDurationDoesNotFireSustained() {
        let evidence = AwakeEvidenceModel.evaluate(input(duration: .infinity))
        XCTAssertFalse(evidence.presentFactors.contains(.sustainedEpisode))
        XCTAssertEqual(evidence.likelihood, .notEnough)
    }

    func testNegativeRecencyDoesNotFireRecentMovement() {
        let evidence = AwakeEvidenceModel.evaluate(input(recency: -100))
        XCTAssertFalse(evidence.presentFactors.contains(.recentMovement))
        XCTAssertEqual(evidence.likelihood, .notEnough)
    }

    func testNaNRecencyDoesNotFireRecentMovement() {
        let evidence = AwakeEvidenceModel.evaluate(input(recency: .nan))
        XCTAssertFalse(evidence.presentFactors.contains(.recentMovement))
    }

    func testOverflowingStepCountsDoNotTrap() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let episodes = [
            MovementEpisode(
                start: base, end: base.addingTimeInterval(25), stepCount: .max,
                observationCount: 26),
            MovementEpisode(
                start: base.addingTimeInterval(30), end: base.addingTimeInterval(60),
                stepCount: .max, observationCount: 26),
        ]
        let evidence = AwakeEvidenceModel.evaluate(
            episodes: episodes, deviceInteracted: false, now: base.addingTimeInterval(70))
        XCTAssertTrue(
            evidence.presentFactors.contains(.recentSteps), "saturated sum still fires the gate")
    }

    // MARK: - Documented residual: passive transport reads as awake (no activity discriminator)

    /// KNOWN LIMITATION (WG-080): the model has no activity/cadence discriminator, so passive
    /// transport — a phone accruing pedometer steps in a bag on a moving vehicle — corroborates
    /// recent-steps + sustained + recency and reads as `.likely`. Pinned intentionally; tolerable
    /// only because the model is advisory and can never suppress an alarm (#8). If a future task
    /// adds a transport gate, update this expectation.
    func testPassiveTransportReadsAsAwakeKnownLimitation() {
        let transport = input(steps: 400, duration: 1800, recency: 5, device: false)
        XCTAssertEqual(AwakeEvidenceModel.evaluate(transport).likelihood, .likely)
    }
}
