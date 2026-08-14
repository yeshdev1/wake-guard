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

    /// Fuse a cadence verdict into a corroboration signal (WG-243, rescoped WG-295 after device
    /// calibration). A plausible gait corroborates. **Only `.implausiblyFast` contradicts** (wipes
    /// banked progress): a sub-band interval means ≥4 steps/s sustained across a delivery pair — a
    /// shake's positive signature a real gait cannot produce. Erratic/metronomic verdicts on
    /// delivery-reconstructed data are usually mixed delivery gaps / the delivery timer itself (the
    /// device finding that wiped real walkers' progress), so they **hold** (`.unavailable`) rather than
    /// contradict — progress banks but can never pass on them, keeping #20 intact: a shake alone still
    /// never passes; only a plausible-gait window does.
    init(cadence verdict: CadenceVerdict) {
        switch verdict {
        case .plausibleGait:
            self = .corroborated
        case .implausiblyFast:
            self = .contradicted
        case .tooFewSteps, .implausibleTiming, .tooErratic, .tooRegular:
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
