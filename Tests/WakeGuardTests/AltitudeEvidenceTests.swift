import XCTest

@testable import WakeGuard

/// WG-066: the optional altimeter evidence analyzer. Verifies that a real fast vertical change
/// corroborates movement, that **slow pressure drift never does** (the anti-cheat), that an
/// unavailable barometer is neutral (no negative impact), and that the evidence is supporting-only
/// (no case a consumer treats as a failure). The CMAltimeter adapter itself is device-only.
final class AltitudeEvidenceTests: XCTestCase {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(_ offset: TimeInterval, altitude: Double) -> AltitudeSample {
        AltitudeSample(
            timestamp: Self.base.addingTimeInterval(offset), quality: .high,
            relativeAltitudeMeters: altitude, pressureKilopascals: nil)
    }

    private func evaluate(
        _ samples: [AltitudeSample], availability: MotionSourceAvailability = .available
    ) -> AltitudeEvidence {
        AltitudeEvidenceAnalyzer.evaluate(samples, availability: availability)
    }

    // MARK: - Real vertical change corroborates

    func testFastRiseCorroboratesMovement() {
        // ~0.9 m over 2 s — a stand-up / first stair.
        let altitudes = [0.0, 0.5, 1.0, 1.4, 1.5]
        let samples = altitudes.enumerated().map {
            sample(Double($0.offset) * 0.5, altitude: $0.element)
        }
        let evidence = evaluate(samples)
        XCTAssertEqual(evidence, .significantChange)
        XCTAssertTrue(evidence.corroboratesMovement)
    }

    func testFastDescentAlsoCorroborates() {
        // Direction-agnostic: going down stairs is also physical movement.
        let altitudes = [0.0, -0.5, -1.0, -1.4, -1.5]
        let samples = altitudes.enumerated().map {
            sample(Double($0.offset) * 0.5, altitude: $0.element)
        }
        XCTAssertEqual(evaluate(samples), .significantChange)
    }

    // MARK: - Drift must NOT pass (the anti-cheat)

    func testSlowDriftReachingMagnitudeIsStillFlat() {
        // Barometric drift ramps a full ~0.8 m, but over 60 s — rate ~0.013 m/s, far below a real
        // move. Must stay `.flat` (pressure drift does not pass a challenge).
        let altitudes = [0.0, 0.4, 0.8, 1.2, 1.6]
        let samples = altitudes.enumerated().map {
            sample(Double($0.offset) * 15.0, altitude: $0.element)
        }
        let evidence = evaluate(samples)
        XCTAssertEqual(evidence, .flat)
        XCTAssertFalse(evidence.corroboratesMovement)
    }

    func testSmallDriftIsFlat() {
        let altitudes = [0.0, 0.02, 0.05, 0.03, 0.06]
        let samples = altitudes.enumerated().map { sample(Double($0.offset), altitude: $0.element) }
        XCTAssertEqual(evaluate(samples), .flat)
    }

    func testNoChangeIsFlat() {
        let samples = (0..<5).map { sample(Double($0), altitude: 0.0) }
        XCTAssertEqual(evaluate(samples), .flat)
    }

    func testSingleAltitudeSpikeDoesNotManufactureChange() {
        // A flat window with one spiky sample — the median endpoints reject it.
        let altitudes = [0.0, 0.01, 0.9, 0.02, 0.03]
        let samples = altitudes.enumerated().map {
            sample(Double($0.offset) * 0.5, altitude: $0.element)
        }
        XCTAssertEqual(evaluate(samples), .flat)
    }

    // MARK: - Unavailable / insufficient are neutral

    func testUnavailableBarometerIsNeutral() {
        // Even with sample data present, a non-available source is neutral — never a penalty.
        let altitudes = [0.0, 0.5, 1.0, 1.4, 1.5]
        let samples = altitudes.enumerated().map {
            sample(Double($0.offset) * 0.5, altitude: $0.element)
        }
        let unavailableStates: [MotionSourceAvailability] = [
            .notPresent, .notAuthorized, .restricted, .temporarilyUnavailable,
        ]
        for availability in unavailableStates {
            let evidence = evaluate(samples, availability: availability)
            XCTAssertEqual(evidence, .unavailable)
            XCTAssertFalse(
                evidence.corroboratesMovement, "an unavailable barometer never corroborates")
        }
    }

    func testTooFewSamplesIsInsufficient() {
        let samples = (0..<3).map { sample(Double($0), altitude: Double($0)) }
        XCTAssertEqual(evaluate(samples), .insufficient)
    }

    func testNonFiniteAltitudeIsInsufficient() {
        var samples = (0..<5).map { sample(Double($0) * 0.5, altitude: Double($0) * 0.4) }
        samples[2] = sample(1.0, altitude: .nan)
        XCTAssertEqual(evaluate(samples), .insufficient)
    }

    func testZeroDurationWindowIsInsufficient() {
        // All samples share a timestamp — no time base for a rate, so no claim.
        let samples = (0..<5).map { _ in sample(0, altitude: 1.0) }
        XCTAssertEqual(evaluate(samples), .insufficient)
    }

    func testEmptyIsInsufficient() {
        XCTAssertEqual(evaluate([]), .insufficient)
    }

    // MARK: - Supporting-only invariant

    func testOnlySignificantChangeCorroborates() {
        // The supporting-only guarantee: exactly one case corroborates, none is a failure.
        for evidence in AltitudeEvidence.allCases {
            XCTAssertEqual(
                evidence.corroboratesMovement, evidence == .significantChange,
                "\(evidence) corroboration must match significantChange only")
        }
    }
}
