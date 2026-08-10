import Foundation
import Observation

/// Drives the readiness card (WG-130): queries recent sleep, computes the assessment, and holds it for the
/// UI. Degrades safely across every HealthKit access state — a **denied / revoked / errored** query
/// returns no samples (or throws), which yields an assessment with **no factors** ("not enough data"),
/// never a crash. It is **recomputed on every refresh**, so a revocation replaces any prior value and
/// **no stale readiness claim remains**. `@MainActor` because it feeds SwiftUI directly; holds no alarm
/// authority.
@MainActor
@Observable
final class ReadinessViewModel {
    /// The current readiness, or `nil` before the first refresh. After a refresh it always reflects the
    /// **current** data — an unavailable one has no factors.
    private(set) var assessment: ReadinessAssessment?

    private let sleepQuery: any SleepSampleQuerying
    private let need: SleepNeed
    private let calendar: Calendar
    private let lookback: TimeInterval

    init(
        sleepQuery: any SleepSampleQuerying, need: SleepNeed = .default,
        calendar: Calendar = Calendar(identifier: .gregorian), lookback: TimeInterval = 14 * 86_400
    ) {
        self.sleepQuery = sleepQuery
        self.need = need
        self.calendar = calendar
        self.lookback = lookback
    }

    /// Recompute readiness from the current data. Never throws or crashes: a denied/revoked/errored query
    /// degrades to an unavailable ("not enough data") assessment, replacing any prior value.
    func refresh(now: Date) async {
        let samples =
            (try? await sleepQuery.sleepSamples(from: now.addingTimeInterval(-lookback), to: now))
            ?? []
        assessment = ReadinessComputer.readiness(from: samples, need: need, calendar: calendar)
    }
}
