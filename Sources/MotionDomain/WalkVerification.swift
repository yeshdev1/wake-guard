import Foundation

/// The outcome of verifying whether observed movement constitutes a validated sustained walk
/// (WG-069). There is deliberately **no `failed` case**: a movement inference alone never fails a
/// challenge (#21) — the verifier only ever *confirms a walk* or reports *not yet*, and the timeout
/// (WG-068) is what turns "not yet" into a kept alarm. String-raw so an unknown value fails to
/// decode (#27).
enum WalkVerification: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// A validated sustained walk — long enough, dense enough, with enough real steps.
    case passed
    /// Movement seen but not yet a validated walk (too short, too sparse, or too few steps) — the
    /// challenge stays active; only a timeout fails it.
    case insufficient
}

/// The requirements a movement episode must meet to count as a validated walk (WG-069), **clamped
/// within safe bounds**. A challenge may be made *stricter* (longer, more steps, denser) but never
/// weaker than these floors — a mis-set or adversarial config cannot create a trivially-passable
/// challenge. The ten-second duration floor is the task's namesake.
struct WalkRequirements: Sendable, Equatable {
    /// Minimum continuous walking duration.
    let minimumDuration: TimeInterval
    /// Minimum real steps within the episode (rejects a stationary pickup / device-only motion).
    let minimumSteps: Int
    /// The laxest allowed mean gap between observations — the density bar that rejects a sparse
    /// injected/replayed "episode"; a *smaller* value is stricter.
    let maximumMeanGap: TimeInterval

    // Safe bounds — the challenge is clamped into these; it can be stricter, never weaker.
    static let minimumDurationFloor: TimeInterval = 10
    static let minimumDurationCeiling: TimeInterval = 120
    static let minimumStepsFloor = 10
    static let minimumStepsCeiling = 200
    /// Density: a larger mean gap is *more lenient*, so the ceiling is the laxest allowed; the floor
    /// keeps a config from demanding an impossibly dense stream.
    static let maximumMeanGapFloor: TimeInterval = 0.2
    static let maximumMeanGapCeiling: TimeInterval = 2.0

    init(
        minimumDuration: TimeInterval = minimumDurationFloor,
        minimumSteps: Int = minimumStepsFloor,
        maximumMeanGap: TimeInterval = maximumMeanGapCeiling
    ) {
        self.minimumDuration = Self.clamped(
            minimumDuration, low: Self.minimumDurationFloor, high: Self.minimumDurationCeiling,
            fallback: Self.minimumDurationFloor)
        self.minimumSteps = min(Self.minimumStepsCeiling, max(Self.minimumStepsFloor, minimumSteps))
        self.maximumMeanGap = Self.clamped(
            maximumMeanGap, low: Self.maximumMeanGapFloor, high: Self.maximumMeanGapCeiling,
            fallback: Self.maximumMeanGapCeiling)
    }

    /// Clamp into `[low, high]`; a non-finite input falls to `fallback` — the field's safe default
    /// (the ten-second floor for duration, the standard bar for density), never infinitely lenient.
    private static func clamped(_ value: Double, low: Double, high: Double, fallback: Double)
        -> Double
    {
        guard value.isFinite else { return fallback }
        return min(high, max(low, value))
    }
}

/// Verifies whether movement episodes (WG-067) contain a validated sustained walk (WG-069). It
/// applies three gates that reject the *trivial* fakes — **duration** (≥ the ten-second floor, so a
/// short movement fails), **step count** (real stepping, so a device-only stationary pickup fails),
/// and **density** (mean inter-observation gap, so a sparse injected episode fails).
///
/// **It does not defeat a regular-cadence shake.** CMPedometer counts shake accelerations as steps
/// and WG-067 treats every pedometer sample as movement, so a sustained shake that yields pedometer
/// steps clears all three gates — this layer does **not** measure step *regularity*. That shake /
/// replay defense is WG-070's job (backlog: "rapid irregular motion without pedometer evidence
/// fails"); until it lands, a shake producing pedometer steps passes here. So this is the *validated
/// walk* check, not the whole anti-cheat. Pure and deterministic.
struct WalkVerifier: Sendable, Equatable {
    let requirements: WalkRequirements

    init(requirements: WalkRequirements = WalkRequirements()) {
        self.requirements = requirements
    }

    /// `.passed` if any episode is a validated walk, otherwise `.insufficient` (never `.failed` — the
    /// timeout owns failure, #21).
    func verify(_ episodes: [MovementEpisode]) -> WalkVerification {
        episodes.contains(where: isValidWalk) ? .passed : .insufficient
    }

    /// Whether a single episode meets every requirement (all conjunctive). Fails closed on a
    /// non-finite / negative duration, independent of the producer. `stepCount` is WG-067's
    /// *advisory* count, used here only as an inflation-proof **lower bound** (it can't be fabricated
    /// upward, so a stepless pickup fails). The mean-gap density check is a coarse backstop — WG-067's
    /// `pauseGap` already caps any single within-episode gap, and true cadence *regularity* is
    /// WG-070's. A short walk, a stepless pickup, and a sparse episode each fail exactly one gate.
    func isValidWalk(_ episode: MovementEpisode) -> Bool {
        guard episode.duration.isFinite, episode.duration >= 0 else { return false }
        guard episode.observationCount >= 2 else { return false }
        guard episode.duration >= requirements.minimumDuration else { return false }
        guard episode.stepCount >= requirements.minimumSteps else { return false }
        let meanGap = episode.duration / Double(episode.observationCount - 1)
        return meanGap <= requirements.maximumMeanGap
    }
}
