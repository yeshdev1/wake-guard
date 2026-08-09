import XCTest

@testable import WakeGuard

/// WG-075: the calibration profile that the real-device study fills in. Verifies the baseline uses
/// the analyzers' defaults, that a profile round-trips, that it stores **no participant identifiers**
/// (only tuning parameters), and that a persisted profile can never weaken the walk below its safe
/// floor (`WalkRequirements` re-clamps on decode).
final class CalibrationProfileTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 75)

    func testBaselineUsesAnalyzerDefaults() {
        let profile = CalibrationProfile.baseline(id: CalibrationProfileID(ids.next()))
        XCTAssertEqual(profile.walk, WalkRequirements())
        XCTAssertEqual(profile.deviceMotion, .default)
        XCTAssertEqual(profile.altitude, .default)
        XCTAssertEqual(profile.cadence, .default)
    }

    func testRoundTrips() throws {
        let profile = CalibrationProfile.baseline(id: CalibrationProfileID(ids.next()))
        let data = try JSONEncoder().encode(profile)
        XCTAssertEqual(try JSONDecoder().decode(CalibrationProfile.self, from: data), profile)
    }

    func testStoresNoParticipantIdentifiers() throws {
        let profile = CalibrationProfile.baseline(id: CalibrationProfileID(ids.next()))
        let data = try JSONEncoder().encode(profile)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys), ["id", "deviceMotion", "altitude", "walk", "cadence"],
            "the profile stores only tuning parameters + its own id — no participant identifier")
        // Recursively confirm no nested key is a participant identifier (structural, not just
        // top-level, so a future nested field can't smuggle one in).
        let forbidden = [
            "name", "participant", "email", "user", "latitude", "longitude", "location", "subject",
            "personal", "phone", "address",
        ]
        for key in Self.allKeys(object) {
            let lower = key.lowercased()
            XCTAssertFalse(
                forbidden.contains { lower.contains($0) }, "unexpected identifying key: \(key)")
        }
    }

    private static func allKeys(_ value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            return Array(dictionary.keys) + dictionary.values.flatMap(allKeys)
        }
        if let array = value as? [Any] {
            return array.flatMap(allKeys)
        }
        return []
    }

    func testWalkRequirementsReClampBelowSafeFloorOnDecode() throws {
        // A persisted profile that tries to weaken the walk below the ten-second floor.
        let json = Data(#"{"minimumDuration":2,"minimumSteps":1,"maximumMeanGap":100}"#.utf8)
        let decoded = try JSONDecoder().decode(WalkRequirements.self, from: json)
        XCTAssertEqual(
            decoded.minimumDuration, 10, "decode re-clamps to the ten-second floor — never weaker")
        XCTAssertEqual(decoded.minimumSteps, 10)
        XCTAssertEqual(decoded.maximumMeanGap, 2.0)
    }

    func testLenientAdvisoryThresholdsCannotFlipANonWalkToPass() {
        // The advisory analyzers (device-motion / altitude / cadence) never gate a pass — only the
        // re-clamped `WalkRequirements` does. So even wildly lenient advisory thresholds can't make a
        // short, stepless (non-walk) episode pass.
        let profile = CalibrationProfile(
            id: CalibrationProfileID(ids.next()),
            deviceMotion: DeviceMotionEvidenceAnalyzer.Thresholds(
                minSamples: 1, stationaryMaxAcceleration: 100, stationaryMaxRotation: 100,
                stationaryMaxAngleRange: 100, pickupMinAngleChange: 0, shakingMinAcceleration: 100,
                shakingMinAngleVariability: 100),
            altitude: AltitudeEvidenceAnalyzer.Thresholds(
                minSamples: 1, minSignificantChange: 0, minChangeRate: 0),
            walk: WalkRequirements(),
            cadence: CadenceThresholds(
                minimumIntervals: 1, minStepInterval: 0, maxStepInterval: 100,
                minCoefficientOfVariation: 0, maxCoefficientOfVariation: 100))
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let nonWalk = MovementEpisode(
            start: base, end: base.addingTimeInterval(3), stepCount: 0, observationCount: 4)
        XCTAssertEqual(
            WalkVerifier(requirements: profile.walk).verify([nonWalk]), .insufficient,
            "the walk gate is authoritative — advisory thresholds can't manufacture a pass")
    }
}
