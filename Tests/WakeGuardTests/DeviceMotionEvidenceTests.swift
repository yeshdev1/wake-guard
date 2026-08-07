import XCTest

@testable import WakeGuard

/// WG-065: the device-carried / pickup evidence analyzer. Trace-tests that a window of
/// `DeviceMotionSample` is classified conservatively into stationary / pickup / irregular-shaking,
/// that ambiguous, corrupt, orientation-less, or too-short windows yield `insufficient` (never a
/// false positive), and that a shake or a forceful reorientation is never credited as a pickup. The
/// evidence carries no distance/position — it cannot claim physical displacement by construction.
final class DeviceMotionEvidenceTests: XCTestCase {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        _ offset: TimeInterval, accel: Double, rotation: Double, angle: Double?
    ) -> DeviceMotionSample {
        DeviceMotionSample(
            timestamp: Self.base.addingTimeInterval(offset), quality: .high,
            userAccelerationMagnitude: accel, rotationRateMagnitude: rotation,
            gravityAngleFromVerticalRadians: angle)
    }

    private func character(_ samples: [DeviceMotionSample]) -> DeviceMotionCharacter {
        DeviceMotionEvidenceAnalyzer.evaluate(samples).character
    }

    // MARK: - Positive classes

    func testStationaryWhenStillAndFixedOrientation() {
        let samples = (0..<6).map {
            sample(Double($0), accel: 0.02, rotation: 0.03, angle: 1.40 + Double($0) * 0.002)
        }
        XCTAssertEqual(character(samples), .stationary)
    }

    func testPickupWhenSettledReorientationWithGentleMotion() {
        // Orientation sweeps from lying flat (~1.4 rad) to held (~0.3 rad) and settles; motion is
        // present but not forceful.
        let angles = [1.40, 1.30, 1.00, 0.60, 0.40, 0.30]
        let accels = [0.02, 0.20, 0.35, 0.30, 0.15, 0.05]
        let samples = (0..<6).map {
            sample(Double($0), accel: accels[$0], rotation: 0.2, angle: angles[$0])
        }
        XCTAssertEqual(character(samples), .pickup)
    }

    func testIrregularShakingWhenForcefulWithoutReorientation() {
        // High acceleration, orientation wobbles wide but returns (net change ~0).
        let angles = [1.40, 1.10, 1.70, 1.00, 1.60, 1.40]
        let accels = [0.90, 1.50, 1.20, 1.40, 1.10, 0.95]
        let samples = (0..<6).map {
            sample(Double($0), accel: accels[$0], rotation: 2.0, angle: angles[$0])
        }
        XCTAssertEqual(character(samples), .irregularShaking)
    }

    func testIrregularShakingWhenErraticOrientationWithoutReorientation() {
        // Lower acceleration, but a wide erratic angle swing that nets to ~0 — still a shake.
        let angles = [1.40, 0.90, 1.70, 0.95, 1.65, 1.42]
        let samples = (0..<6).map {
            sample(Double($0), accel: 0.40, rotation: 0.6, angle: angles[$0])
        }
        XCTAssertEqual(character(samples), .irregularShaking)
    }

    // MARK: - Conservative no-claim cases

    func testForcefulReorientationIsNotCreditedAsPickup() {
        // A clear net reorientation BUT forceful (a violent grab) — must not be a `pickup`, and it
        // reoriented so it isn't `irregularShaking` either → conservative `insufficient`.
        let angles = [1.50, 1.45, 1.40, 0.30, 0.25, 0.20]
        let samples = (0..<6).map {
            sample(Double($0), accel: 1.50, rotation: 2.0, angle: angles[$0])
        }
        XCTAssertEqual(character(samples), .insufficient)
    }

    func testGlitchedEndpointDoesNotManufacturePickup() {
        // An otherwise-flat window with one glitched first angle: the raw first/last would fake a
        // net reorientation of ~0.57 rad and read as pickup; the head/tail median rejects the lone
        // outlier, so it is never a false carry (review A2a).
        let angles = [0.85, 1.40, 1.41, 1.40, 1.41, 1.42]
        let samples = (0..<6).map {
            sample(Double($0), accel: 0.30, rotation: 0.1, angle: angles[$0])
        }
        XCTAssertNotEqual(
            character(samples), .pickup, "a single orientation glitch must not fake a pickup")
    }

    func testSubThresholdShakeWithNarrowWobbleIsInsufficient() {
        // Vigorous but sub-0.8g motion with a narrow (<0.5 rad) wobble and no net reorientation —
        // escapes both stationary and the shaking branch, and lands in the conservative sink.
        let angles = [1.40, 1.25, 1.55, 1.30, 1.50, 1.40]
        let samples = (0..<6).map {
            sample(Double($0), accel: 0.50, rotation: 1.5, angle: angles[$0])
        }
        XCTAssertEqual(character(samples), .insufficient)
    }

    func testSlowDeliberateTiltIsPickupByDesign() {
        // A gentle flat->upright tilt without getting up is indistinguishable from a real pickup and
        // is intentionally classified `.pickup` — a documented limitation; the real wake gate is the
        // walking verification (WG-069), which must not treat pickup as a walk.
        let angles = [1.40, 1.15, 0.90, 0.65, 0.40, 0.20]
        let samples = (0..<6).map {
            sample(Double($0), accel: 0.25, rotation: 0.4, angle: angles[$0])
        }
        XCTAssertEqual(character(samples), .pickup)
    }

    func testAmbiguousModerateMotionIsInsufficient() {
        // Moderate everything, small reorientation — fits no class cleanly.
        let angles = [1.40, 1.35, 1.25, 1.20, 1.15, 1.12]
        let samples = (0..<6).map {
            sample(Double($0), accel: 0.30, rotation: 0.2, angle: angles[$0])
        }
        XCTAssertEqual(character(samples), .insufficient)
    }

    func testTooFewSamplesIsInsufficient() {
        let samples = (0..<3).map { sample(Double($0), accel: 0.3, rotation: 0.2, angle: 1.0) }
        let evidence = DeviceMotionEvidenceAnalyzer.evaluate(samples)
        XCTAssertEqual(evidence.character, .insufficient)
        XCTAssertEqual(evidence.sampleCount, 3, "the window is still summarized")
    }

    func testMissingOrientationIsInsufficient() {
        // Plenty of samples and clear motion, but no gravity angle → can't separate carry from
        // shake → no claim.
        let samples = (0..<6).map { sample(Double($0), accel: 0.6, rotation: 1.0, angle: nil) }
        XCTAssertEqual(character(samples), .insufficient)
    }

    func testNonFiniteMagnitudeIsInsufficient() {
        var samples = (0..<6).map { sample(Double($0), accel: 0.02, rotation: 0.02, angle: 1.4) }
        samples[2] = sample(2, accel: .nan, rotation: 0.02, angle: 1.4)
        XCTAssertEqual(character(samples), .insufficient)
    }

    func testEmptyWindowIsInsufficientWithNilWindow() {
        let evidence = DeviceMotionEvidenceAnalyzer.evaluate([])
        XCTAssertEqual(evidence, .empty)
        XCTAssertNil(evidence.windowStart)
        XCTAssertEqual(evidence.sampleCount, 0)
    }

    // MARK: - Window retention

    func testEvidenceRetainsWindowBounds() {
        let samples = (0..<6).map {
            sample(Double($0), accel: 0.02, rotation: 0.03, angle: 1.40)
        }
        let evidence = DeviceMotionEvidenceAnalyzer.evaluate(samples)
        XCTAssertEqual(evidence.sampleCount, 6)
        XCTAssertEqual(evidence.windowStart, Self.base)
        XCTAssertEqual(evidence.windowEnd, Self.base.addingTimeInterval(5))
    }
}
