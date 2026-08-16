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

    /// A motion-based **estimate** of overnight disturbances (WG-310/312) — the "Movement overnight" section,
    /// now shown **always** (alongside any HealthKit sleep data, WG-312), not only as a fallback. `nil` when
    /// unavailable (denied motion access, no history, or no motion source wired).
    private(set) var estimatedDisturbances: SleepDisturbances?

    /// A motion-based **estimate** of the longest low-activity (rest) stretch overnight (WG-311), in
    /// seconds — part of the "Movement overnight" section. **Not sleep and not a readiness factor** (a still
    /// phone isn't a sleeping person); shown only as a clearly-labelled estimate. Same availability rule as
    /// `estimatedDisturbances` (both from one motion query).
    private(set) var estimatedRest: TimeInterval?

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
        await applyMovementSummary(now: now)
    }

    /// The always-on movement summary (WG-310/311/312): whenever a motion source is wired, one query
    /// populates **both** the disturbance and rest estimates — shown alongside any HealthKit sleep data, no
    /// longer gated on HealthKit being empty. A denied/unavailable/errored query leaves them `nil` (no
    /// section shown), never a fabricated value. Both reset each refresh, so a revoked grant never leaves a
    /// stale estimate on screen.
    private func applyMovementSummary(now: Date) async {
        estimatedDisturbances = nil
        estimatedRest = nil
        guard let motionHistory else { return }
        let window = SleepDisturbanceEstimator.overnightWindow(endingAt: now)
        guard let samples = try? await motionHistory.activitySamples(in: window) else { return }
        estimatedDisturbances = SleepDisturbanceEstimator.estimate(samples: samples, window: window)
        estimatedRest = SleepDisturbanceEstimator.longestRestWindow(
            samples: samples, window: window)
    }
}
