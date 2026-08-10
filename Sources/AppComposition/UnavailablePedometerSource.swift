import Foundation

/// A `HistoricalPedometerSource` that reports no hardware, for the in-memory (test/preview) graph's
/// pre-alarm pipeline: previews / UI tests never read Core Motion, so the pipeline always declines
/// (`.sourceUnavailable`) and no prompt is posted. The production graph composes the real
/// `CoreMotionHistoricalPedometerAdapter`.
struct UnavailablePedometerSource: HistoricalPedometerSource {
    func availability() async -> MotionSourceAvailability { .notPresent }

    func samples(in window: PedometerQueryWindow) async throws -> [PedometerSample] {
        throw MotionSourceError.unavailable(.notPresent)
    }
}
