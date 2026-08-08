#if DEBUG

    import Foundation

    /// One recorded motion sample (WG-074, **DEBUG-only**). It is stored re-timestamped to a
    /// *relative* offset from the trace start, so the export carries no absolute wall-clock time that
    /// could reveal when the user slept. The WG-060 samples already carry only motion magnitudes / a
    /// single orientation scalar and **no identifier**, so a relative-time trace is anonymized.
    enum RecordedMotionSample: Codable, Sendable, Equatable {
        case pedometer(PedometerSample)
        case activity(MotionActivitySample)
        case deviceMotion(DeviceMotionSample)
        case altitude(AltitudeSample)

        var timestamp: Date {
            switch self {
            case .pedometer(let sample): return sample.timestamp
            case .activity(let sample): return sample.timestamp
            case .deviceMotion(let sample): return sample.timestamp
            case .altitude(let sample): return sample.timestamp
            }
        }

        /// A copy with the timestamp replaced by its **offset from `base`** (as `epoch + seconds`), so
        /// the absolute time is erased — only relative timing, the calibration signal, remains.
        func rebased(to base: Date) -> RecordedMotionSample {
            let offset = Date(timeIntervalSince1970: timestamp.timeIntervalSince(base))
            switch self {
            case .pedometer(let sample):
                return .pedometer(
                    PedometerSample(
                        timestamp: offset, quality: sample.quality, stepCount: sample.stepCount,
                        distanceMeters: sample.distanceMeters,
                        cadenceStepsPerSecond: sample.cadenceStepsPerSecond,
                        secondsSinceLastStep: sample.secondsSinceLastStep))
            case .activity(let sample):
                return .activity(
                    MotionActivitySample(
                        timestamp: offset, quality: sample.quality, kind: sample.kind))
            case .deviceMotion(let sample):
                return .deviceMotion(
                    DeviceMotionSample(
                        timestamp: offset, quality: sample.quality,
                        userAccelerationMagnitude: sample.userAccelerationMagnitude,
                        rotationRateMagnitude: sample.rotationRateMagnitude,
                        gravityAngleFromVerticalRadians: sample.gravityAngleFromVerticalRadians))
            case .altitude(let sample):
                return .altitude(
                    AltitudeSample(
                        timestamp: offset, quality: sample.quality,
                        relativeAltitudeMeters: sample.relativeAltitudeMeters,
                        pressureKilopascals: sample.pressureKilopascals))
            }
        }
    }

    /// An **anonymized** motion trace (WG-074, DEBUG-only): a label + the re-based samples, exportable
    /// as JSON for internal calibration (WG-075). It carries **no absolute time, no user / device /
    /// alarm identifier, and no location** — only motion magnitudes on a relative timeline.
    struct MotionTrace: Codable, Sendable, Equatable {
        let label: String
        /// Samples whose timestamps are relative offsets (`epoch + seconds`) from the trace start.
        let samples: [RecordedMotionSample]

        /// The trace length in seconds (the last relative offset).
        var duration: TimeInterval { samples.last?.timestamp.timeIntervalSince1970 ?? 0 }

        /// Export as JSON with **relative-offset** date encoding, so a timestamp serializes as its
        /// seconds-from-start (e.g. `1.5`), never a wall-clock instant.
        func exportJSON() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .secondsSince1970
            return try encoder.encode(self)
        }

        /// Decode a trace exported by `exportJSON()` (matching relative-offset date decoding).
        static func decode(_ data: Data) throws -> MotionTrace {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(MotionTrace.self, from: data)
        }
    }

    /// A DEBUG-only motion-trace recorder for internal testing (WG-074). It records the WG-060 motion
    /// samples into an **anonymized** `MotionTrace` (relative time, no identifiers) for on-device
    /// calibration (WG-075). **Production builds exclude it** — the whole file is `#if DEBUG`, so the
    /// recorder does not exist in the App Store archive. Capture is **gated on explicit consent**
    /// (`consentWarning`); without it, recording is a fail-closed no-op. One recorder instance is
    /// **one consented session** — consent is fixed at init; re-consent by constructing a new
    /// recorder. Note the exported trace is *pseudonymous-behavioral* (a gait/step series can be
    /// fingerprinted given external reference data), so it must stay on-device / internal, never
    /// distributed (see the WG-074 ADR).
    final class MotionTraceRecorder {
        /// The warning an internal tester must acknowledge before recording — it states what is
        /// captured and that the export is anonymized and internal-only.
        static let consentWarning = """
            This records your motion — step counts, movement magnitudes, and device orientation — for \
            internal WakeGuard testing. The exported trace is anonymized: it has no timestamps that \
            reveal when you slept, and no name, device, or location. It is captured only in internal \
            debug builds, never in the App Store app.
            """

        private let consented: Bool
        private var base: Date?
        private var samples: [RecordedMotionSample] = []

        /// - Parameter consented: whether the tester acknowledged `consentWarning`. When `false`,
        ///   every `record` is a no-op — nothing is captured without consent.
        init(consented: Bool) {
            self.consented = consented
        }

        var isRecording: Bool { consented }
        var sampleCount: Int { samples.count }

        /// Record a sample (anonymized on capture). A **no-op unless the tester consented**.
        func record(_ sample: RecordedMotionSample) {
            guard consented else { return }
            if base == nil { base = sample.timestamp }
            guard let base else { return }
            samples.append(sample.rebased(to: base))
        }

        func record(_ sample: PedometerSample) { record(.pedometer(sample)) }
        func record(_ sample: MotionActivitySample) { record(.activity(sample)) }
        func record(_ sample: DeviceMotionSample) { record(.deviceMotion(sample)) }
        func record(_ sample: AltitudeSample) { record(.altitude(sample)) }

        /// The anonymized trace captured so far. `label` is a free-text tag for the run (e.g.
        /// "slow-walk") — an internal tester must not put personal information in it.
        func makeTrace(label: String) -> MotionTrace {
            MotionTrace(label: label, samples: samples)
        }
    }

#endif
