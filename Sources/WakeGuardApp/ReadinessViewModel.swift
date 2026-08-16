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

    /// Last night's mid-sleep interruptions (WG-309), or `nil` when there is no sleep data. Recomputed on
    /// every refresh from the same samples, so it never outlives a revoked grant.
    private(set) var lastNightInterruptions: SleepInterruptions?

    /// A motion-based **estimate** of overnight disturbances (WG-310), computed **only** when HealthKit
    /// gives no interruptions (no Apple sleep tracking) — the fallback for users without a Watch. `nil`
    /// when unavailable (denied motion access, no history, or HealthKit already answered).
    private(set) var estimatedDisturbances: SleepDisturbances?

    private let sleepQuery: any SleepSampleQuerying
    private let motionHistory: (any MotionActivityHistorySource)?
    private let need: SleepNeed
    private let calendar: Calendar
    private let lookback: TimeInterval

    init(
        sleepQuery: any SleepSampleQuerying,
        motionHistory: (any MotionActivityHistorySource)? = nil, need: SleepNeed = .default,
        calendar: Calendar = Calendar(identifier: .gregorian), lookback: TimeInterval = 14 * 86_400
    ) {
        self.sleepQuery = sleepQuery
        self.motionHistory = motionHistory
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
        lastNightInterruptions = ReadinessComputer.lastNightInterruptions(from: samples)
        estimatedDisturbances = await motionDisturbances(ifNeeded: lastNightInterruptions, now: now)
    }

    /// The motion fallback (WG-310): only when HealthKit gave **no** interruptions (no sleep data), and only
    /// if a motion source is wired. A denied/unavailable/errored query yields `nil` (no estimate shown),
    /// never a fabricated "undisturbed".
    private func motionDisturbances(ifNeeded interruptions: SleepInterruptions?, now: Date) async
        -> SleepDisturbances?
    {
        guard interruptions == nil, let motionHistory else { return nil }
        let window = SleepDisturbanceEstimator.overnightWindow(endingAt: now)
        guard let samples = try? await motionHistory.activitySamples(in: window) else { return nil }
        return SleepDisturbanceEstimator.estimate(samples: samples, window: window)
    }
}
