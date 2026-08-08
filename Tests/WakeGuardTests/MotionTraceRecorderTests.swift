#if DEBUG

    import XCTest

    @testable import WakeGuard

    /// WG-074: the DEBUG-only motion trace recorder. Verifies capture is gated on consent, that the
    /// recorded trace is anonymized (timestamps become relative offsets — no wall clock, no
    /// identifier), that the JSON export omits absolute time and round-trips, and that the consent
    /// warning states the anonymized / internal-only nature. The whole feature is `#if DEBUG`, so
    /// production builds exclude it (this test compiles only in debug too).
    final class MotionTraceRecorderTests: XCTestCase {

        private let base = Date(timeIntervalSince1970: 1_700_000_000)

        private func pedometer(_ offset: TimeInterval, steps: Int) -> PedometerSample {
            PedometerSample(
                timestamp: base.addingTimeInterval(offset), quality: .high, stepCount: steps)
        }

        // MARK: - Consent gate

        func testConsentGateBlocksCaptureWithoutConsent() {
            let recorder = MotionTraceRecorder(consented: false)
            XCTAssertFalse(recorder.isRecording)
            recorder.record(pedometer(0, steps: 1))
            XCTAssertEqual(recorder.sampleCount, 0, "nothing is captured without consent")
            XCTAssertTrue(recorder.makeTrace(label: "x").samples.isEmpty)
        }

        func testRecordsWithConsent() {
            let recorder = MotionTraceRecorder(consented: true)
            for index in 0..<3 { recorder.record(pedometer(Double(index), steps: index * 2)) }
            XCTAssertEqual(recorder.sampleCount, 3)
        }

        func testConsentWarningStatesAnonymizedAndInternal() {
            let warning = MotionTraceRecorder.consentWarning.lowercased()
            XCTAssertTrue(warning.contains("anonymized"))
            XCTAssertTrue(warning.contains("internal") || warning.contains("debug"))
            XCTAssertTrue(
                warning.contains("app store"), "states it never ships in the App Store app")
        }

        // MARK: - Anonymization

        func testAnonymizesTimestampsToRelativeOffsets() {
            let recorder = MotionTraceRecorder(consented: true)
            recorder.record(pedometer(0, steps: 0))
            recorder.record(pedometer(1.5, steps: 3))
            recorder.record(pedometer(3, steps: 6))
            let trace = recorder.makeTrace(label: "walk")
            XCTAssertEqual(trace.samples.count, 3)
            XCTAssertEqual(
                trace.samples[0].timestamp.timeIntervalSince1970, 0,
                "the first sample is at offset 0")
            XCTAssertEqual(trace.samples[2].timestamp.timeIntervalSince1970, 3)
            XCTAssertEqual(trace.duration, 3)
            XCTAssertFalse(
                trace.samples.contains { $0.timestamp.timeIntervalSince1970 > 1_000_000 },
                "no absolute wall-clock time remains")
        }

        func testExportOmitsAbsoluteTimeAndRoundTrips() throws {
            let recorder = MotionTraceRecorder(consented: true)
            recorder.record(pedometer(0, steps: 0))
            recorder.record(pedometer(2, steps: 4))
            let trace = recorder.makeTrace(label: "walk")
            let data = try trace.exportJSON()
            let json = String(bytes: data, encoding: .utf8) ?? ""
            XCTAssertFalse(
                json.contains("1700000000"), "the export carries no absolute wall-clock time")
            XCTAssertTrue(json.contains("walk"))
            XCTAssertEqual(try MotionTrace.decode(data), trace, "the anonymized trace round-trips")
        }

        func testMixedSampleKindsRoundTrip() throws {
            let recorder = MotionTraceRecorder(consented: true)
            recorder.record(pedometer(0, steps: 5))
            recorder.record(
                MotionActivitySample(
                    timestamp: base.addingTimeInterval(1), quality: .medium, kind: .walking))
            recorder.record(
                DeviceMotionSample(
                    timestamp: base.addingTimeInterval(2), quality: .high,
                    userAccelerationMagnitude: 0.3, rotationRateMagnitude: 0.5))
            recorder.record(
                AltitudeSample(
                    timestamp: base.addingTimeInterval(3), quality: .low,
                    relativeAltitudeMeters: 1.2,
                    pressureKilopascals: nil))
            let trace = recorder.makeTrace(label: "mixed")
            let decoded = try MotionTrace.decode(try trace.exportJSON())
            XCTAssertEqual(decoded, trace)
            XCTAssertEqual(decoded.samples.count, 4)
        }
    }

#endif
