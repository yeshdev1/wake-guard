import Foundation

/// Whether the movement backing counted challenge progress is corroborated as **real gait** (WG-243) — the
/// independent second signal a pass requires (#19), and the gate that stops a shake from passing (#20).
/// Distinct from the step count so the challenge machine can require *both*.
///
/// - `corroborated`: an independent signal confirms a walk (e.g. cadence `.plausibleGait`).
/// - `contradicted`: a **positive** shake / replay signal — this can **never** pass, and it earns no
///   progress (a shake bar can't be banked and then finished with one clean step).
/// - `unavailable`: sensors are too limited to judge — **not** a contradiction, so progress accumulates, but
///   (since a pass requires `.corroborated`) it **never passes on the count alone**. A sensor-poor walker is
///   never trapped: the always-available accessible alternative (#22) is the fallback (#21).
enum MovementCorroboration: String, Sendable, Equatable, Hashable, Codable {
    case corroborated
    case contradicted
    case unavailable

    /// Fuse a cadence verdict into a corroboration signal (WG-243). A plausible gait corroborates; an
    /// **erratic or metronomic** cadence is a positive shake/replay signal and contradicts; an
    /// out-of-band (`.implausibleTiming` — too fast *or* too slow) or too-few-steps verdict can't confidently
    /// judge, so it's `.unavailable` — it never *contradicts* a genuinely slow walker, and (since a pass
    /// requires corroboration) it never lets a fast shake pass either.
    init(cadence verdict: CadenceVerdict) {
        switch verdict {
        case .plausibleGait:
            self = .corroborated
        case .tooErratic, .tooRegular:
            self = .contradicted
        case .tooFewSteps, .implausibleTiming:
            self = .unavailable
        }
    }
}

/// Turns a run's movement observations into the challenge event to apply (WG-243) — the deterministic
/// feeder that fuses the step count with the anti-shake cadence verdict. Pure; the timestamps must be the
/// **sensor-event** times (the cadence series is reconstructed from them), never receipt time, so a batched
/// delivery can't fake an even cadence.
enum ChallengeObservationReducer {
    static func event(
        from observations: [MovementObservation], thresholds: CadenceThresholds = .default
    ) -> WakeChallengeEvent {
        let cumulative = observations.compactMap(\.cumulativeSteps).max() ?? 0
        let corroboration = MovementCorroboration(
            cadence: CadenceRegularity.verify(observations, thresholds: thresholds))
        return .observedProgress(cumulative: cumulative, corroboration: corroboration)
    }
}
