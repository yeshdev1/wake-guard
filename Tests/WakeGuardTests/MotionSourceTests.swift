import XCTest

@testable import WakeGuard

/// WG-060: the normalized motion-source ports. Verifies every sample carries a timestamp + a
/// quality, that the four ports are independent and usable on their own, that an unavailable
/// source is an **explicit** state whose stream throws (never a silent empty), and that unknown
/// enum values fail to decode (#27).
final class MotionSourceTests: XCTestCase {

    private let sampleTime = Date(timeIntervalSince1970: 1_700_000_000)

    private func collect<Sample>(_ stream: AsyncThrowingStream<Sample, Error>) async throws
        -> [Sample]
    {
        var out: [Sample] = []
        for try await sample in stream { out.append(sample) }
        return out
    }

    func testEverySampleExposesTimestampAndQuality() {
        let samples: [any MotionSample] = [
            PedometerSample(
                timestamp: sampleTime, quality: .high, stepCount: 3, distanceMeters: 2.0,
                cadenceStepsPerSecond: 1.5),
            MotionActivitySample(timestamp: sampleTime, quality: .medium, kind: .walking),
            DeviceMotionSample(
                timestamp: sampleTime, quality: .low, userAccelerationMagnitude: 0.2,
                rotationRateMagnitude: 0.1),
            AltitudeSample(
                timestamp: sampleTime, quality: .high, relativeAltitudeMeters: 1.0,
                pressureKilopascals: 101.3),
        ]
        for sample in samples {
            XCTAssertEqual(sample.timestamp, sampleTime, "every sample carries a timestamp")
            XCTAssertTrue(MotionSampleQuality.allCases.contains(sample.quality), "and a quality")
        }
    }

    func testAvailableSourceYieldsItsSamplesInOrder() async throws {
        let s1 = PedometerSample(
            timestamp: sampleTime, quality: .high, stepCount: 1, distanceMeters: nil,
            cadenceStepsPerSecond: nil)
        let s2 = PedometerSample(
            timestamp: sampleTime.addingTimeInterval(1), quality: .high, stepCount: 4,
            distanceMeters: 3.0,
            cadenceStepsPerSecond: 1.6)
        let source: any PedometerSource = FakePedometerSource(cannedSamples: [s1, s2])

        let availability = await source.availability()
        XCTAssertEqual(availability, .available)
        let collected = try await collect(source.samples())
        XCTAssertEqual(collected, [s1, s2])
    }

    func testUnavailableSourceReportsStateAndStreamThrows() async {
        let source = FakePedometerSource(availabilityState: .notAuthorized)
        let availability = await source.availability()
        XCTAssertEqual(availability, .notAuthorized, "unavailability is an explicit state")
        do {
            _ = try await collect(source.samples())
            XCTFail("an unavailable source's stream must throw, not finish silently empty")
        } catch let error as MotionSourceError {
            XCTAssertEqual(error, .unavailable(.notAuthorized))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAllFourPortsAreIndependentlyUsable() async throws {
        let pedometer: any PedometerSource = FakePedometerSource(cannedSamples: [
            PedometerSample(
                timestamp: sampleTime, quality: .high, stepCount: 2, distanceMeters: nil,
                cadenceStepsPerSecond: nil)
        ])
        let activity: any MotionActivitySource = FakeMotionActivitySource(cannedSamples: [
            MotionActivitySample(timestamp: sampleTime, quality: .high, kind: .walking)
        ])
        let deviceMotion: any DeviceMotionSource = FakeDeviceMotionSource(cannedSamples: [
            DeviceMotionSample(
                timestamp: sampleTime, quality: .medium, userAccelerationMagnitude: 0.3,
                rotationRateMagnitude: 0.2)
        ])
        let altimeter: any AltimeterSource = FakeAltimeterSource(cannedSamples: [
            AltitudeSample(
                timestamp: sampleTime, quality: .low, relativeAltitudeMeters: 0.5,
                pressureKilopascals: nil)
        ])

        let pedometerSamples = try await collect(pedometer.samples())
        let activitySamples = try await collect(activity.samples())
        let deviceMotionSamples = try await collect(deviceMotion.samples())
        let altimeterSamples = try await collect(altimeter.samples())
        XCTAssertEqual(pedometerSamples.count, 1)
        XCTAssertEqual(activitySamples.first?.kind, .walking)
        XCTAssertEqual(deviceMotionSamples.count, 1)
        XCTAssertEqual(altimeterSamples.count, 1)
    }

    func testUnknownEnumValuesFailToDecode() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(MotionActivityKind.self, from: Data("\"teleporting\"".utf8)))
        XCTAssertThrowsError(
            try JSONDecoder().decode(MotionSampleQuality.self, from: Data("\"perfect\"".utf8)))
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                MotionSourceAvailability.self, from: Data("\"levitating\"".utf8)))
    }

    func testSamplesCodableRoundTrip() throws {
        let pedometer = PedometerSample(
            timestamp: sampleTime, quality: .medium, stepCount: 12, distanceMeters: 9.0,
            cadenceStepsPerSecond: 1.2)
        XCTAssertEqual(
            try JSONDecoder().decode(PedometerSample.self, from: JSONEncoder().encode(pedometer)),
            pedometer)

        let activity = MotionActivitySample(timestamp: sampleTime, quality: .high, kind: .running)
        XCTAssertEqual(
            try JSONDecoder().decode(
                MotionActivitySample.self, from: JSONEncoder().encode(activity)), activity)
    }

    func testSourceDroppingOutMidStreamThrowsAfterDeliveringSome() async {
        // A sensor that drops out partway must terminate the stream by throwing — never hang, never
        // finish silently empty — so the challenge keeps the alarm and offers the fallback (#21/#24).
        let samples = (0..<4).map {
            PedometerSample(
                timestamp: sampleTime.addingTimeInterval(Double($0)), quality: .high, stepCount: $0)
        }
        let source = FakePedometerSource(cannedSamples: samples, midStreamFailureAfter: 2)
        var delivered: [PedometerSample] = []
        do {
            for try await sample in source.samples() { delivered.append(sample) }
            XCTFail("a mid-attempt sensor drop must throw, not finish cleanly")
        } catch let error as MotionSourceError {
            XCTAssertEqual(delivered.count, 2, "the samples before the drop are delivered")
            XCTAssertEqual(error, .unavailable(.temporarilyUnavailable))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAntiCheatSignalsRoundTrip() throws {
        // The regularity (per-step interval) + carried-vs-shaken (gravity angle) signals the walk
        // challenge needs survive Codable, so they can't be lost across a persisted attempt.
        let pedometer = PedometerSample(
            timestamp: sampleTime, quality: .high, stepCount: 5, distanceMeters: 4.0,
            cadenceStepsPerSecond: 1.8, secondsSinceLastStep: 0.55)
        XCTAssertEqual(
            try JSONDecoder().decode(PedometerSample.self, from: JSONEncoder().encode(pedometer)),
            pedometer)
        XCTAssertEqual(pedometer.secondsSinceLastStep, 0.55)

        let motion = DeviceMotionSample(
            timestamp: sampleTime, quality: .medium, userAccelerationMagnitude: 0.4,
            rotationRateMagnitude: 0.3, gravityAngleFromVerticalRadians: 1.2)
        XCTAssertEqual(
            try JSONDecoder().decode(DeviceMotionSample.self, from: JSONEncoder().encode(motion)),
            motion)
        XCTAssertEqual(motion.gravityAngleFromVerticalRadians, 1.2)
    }
}
