import Foundation

/// A hermetic `MotionActivityHistorySource` for the in-memory graph (WG-310): it returns no samples, so
/// previews/tests never touch CoreMotion and the readiness disturbance fallback stays unavailable (no
/// estimate shown). Production uses `CoreMotionActivityHistoryAdapter`.
struct UnavailableMotionActivityHistory: MotionActivityHistorySource {
    func activitySamples(in window: DateInterval) async throws -> [MotionActivitySample] { [] }
}
