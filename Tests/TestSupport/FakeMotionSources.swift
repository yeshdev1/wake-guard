import Foundation

@testable import WakeGuard

/// Turns canned samples + an availability into an `AsyncThrowingStream` for the motion-source
/// fakes (WG-060): an unavailable source throws `MotionSourceError.unavailable`; otherwise it
/// yields the samples in order and finishes. `failAfter` models a source **dropping out
/// mid-attempt** — it yields that many samples then ends the stream by throwing, so the "sensor
/// dropped partway → keep the alarm, offer the fallback" trace (#21/#24) is testable.
enum FakeMotionStream {
    static func make<Sample: Sendable>(
        _ samples: [Sample], availability: MotionSourceAvailability, failAfter: Int? = nil
    ) -> AsyncThrowingStream<Sample, Error> {
        AsyncThrowingStream { continuation in
            guard availability == .available else {
                continuation.finish(throwing: MotionSourceError.unavailable(availability))
                return
            }
            for (index, sample) in samples.enumerated() {
                if let failAfter, index == failAfter {
                    continuation.finish(
                        throwing: MotionSourceError.unavailable(.temporarilyUnavailable))
                    return
                }
                continuation.yield(sample)
            }
            continuation.finish()
        }
    }
}

/// A configurable `PedometerSource` fake: set the availability, the samples the stream yields, and
/// optionally the index after which the stream drops out mid-attempt. A value type, so `Sendable`.
struct FakePedometerSource: PedometerSource {
    var availabilityState: MotionSourceAvailability = .available
    var cannedSamples: [PedometerSample] = []
    var midStreamFailureAfter: Int?

    func availability() async -> MotionSourceAvailability { availabilityState }

    func samples() -> AsyncThrowingStream<PedometerSample, Error> {
        FakeMotionStream.make(
            cannedSamples, availability: availabilityState, failAfter: midStreamFailureAfter)
    }
}

struct FakeMotionActivitySource: MotionActivitySource {
    var availabilityState: MotionSourceAvailability = .available
    var cannedSamples: [MotionActivitySample] = []
    var midStreamFailureAfter: Int?

    func availability() async -> MotionSourceAvailability { availabilityState }

    func samples() -> AsyncThrowingStream<MotionActivitySample, Error> {
        FakeMotionStream.make(
            cannedSamples, availability: availabilityState, failAfter: midStreamFailureAfter)
    }
}

struct FakeDeviceMotionSource: DeviceMotionSource {
    var availabilityState: MotionSourceAvailability = .available
    var cannedSamples: [DeviceMotionSample] = []
    var midStreamFailureAfter: Int?

    func availability() async -> MotionSourceAvailability { availabilityState }

    func samples() -> AsyncThrowingStream<DeviceMotionSample, Error> {
        FakeMotionStream.make(
            cannedSamples, availability: availabilityState, failAfter: midStreamFailureAfter)
    }
}

struct FakeAltimeterSource: AltimeterSource {
    var availabilityState: MotionSourceAvailability = .available
    var cannedSamples: [AltitudeSample] = []
    var midStreamFailureAfter: Int?

    func availability() async -> MotionSourceAvailability { availabilityState }

    func samples() -> AsyncThrowingStream<AltitudeSample, Error> {
        FakeMotionStream.make(
            cannedSamples, availability: availabilityState, failAfter: midStreamFailureAfter)
    }
}
