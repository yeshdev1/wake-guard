import Foundation

@testable import WakeGuard

/// A configurable `HistoricalPedometerSource` for tests (WG-062): a set availability and canned
/// samples, throwing `MotionSourceError.unavailable` when not available. A value type → Sendable.
struct FakeHistoricalPedometerSource: HistoricalPedometerSource {
    var availabilityState: MotionSourceAvailability = .available
    var cannedSamples: [PedometerSample] = []

    func availability() async -> MotionSourceAvailability { availabilityState }

    func samples(in window: PedometerQueryWindow) async throws -> [PedometerSample] {
        guard availabilityState == .available else {
            throw MotionSourceError.unavailable(availabilityState)
        }
        return cannedSamples
    }
}
