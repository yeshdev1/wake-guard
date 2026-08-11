import Foundation

/// A hermetic `SleepSampleQuerying` for the in-memory graph (WG-121): it returns no samples, so
/// previews/tests never touch HealthKit and readiness degrades to "not enough data" (#36/#38). Production
/// uses `HealthKitSleepQueryAdapter`.
struct UnavailableSleepQuery: SleepSampleQuerying {
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] { [] }
}
