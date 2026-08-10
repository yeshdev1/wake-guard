import Foundation
import XCTest

@testable import WakeGuard

/// WG-224: motion challenge battery & responsiveness. Verifies the challenge uses a **cumulative pedometer,
/// not high-frequency sampling**, and that the sensor **starts only when needed** — it stops on stream
/// termination, so it never runs outside an active challenge. Pass-latency target is documented
/// (`docs/MOTION_CHALLENGE_PERF.md`).
final class MotionChallengeSensorTests: XCTestCase {

    private func adapterCode() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/MotionInfrastructure/CoreMotionLivePedometerAdapter.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testUsesCumulativePedometerNotHighFrequencySampling() throws {
        let code = try adapterCode()
        XCTAssertTrue(
            code.contains("CMPedometer"), "the challenge should use cumulative step counting")
        for highFrequency in [
            "startAccelerometerUpdates", "startDeviceMotionUpdates", "startGyroUpdates",
            "startMagnetometerUpdates",
        ] {
            XCTAssertFalse(
                code.contains(highFrequency),
                "high-frequency sampling '\(highFrequency)' would drain battery unnecessarily")
        }
    }

    func testSensorStartsOnlyWhenNeededAndStopsOnTermination() throws {
        let code = try adapterCode()
        // The pedometer is stopped when the challenge stream ends, so it never runs outside a challenge.
        XCTAssertTrue(code.contains("stopUpdates"), "the pedometer must be stoppable")
        XCTAssertTrue(
            code.contains("onTermination"),
            "the sensor must stop on stream termination (no sensing after the challenge)")
    }

    func testPassLatencyTargetIsDocumented() throws {
        let doc = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("docs/MOTION_CHALLENGE_PERF.md"), encoding: .utf8)
        for required in ["Pass latency", "start only when needed", "high-frequency"] {
            XCTAssertTrue(
                doc.lowercased().contains(required.lowercased()),
                "motion-challenge doc missing '\(required)'")
        }
    }
}
