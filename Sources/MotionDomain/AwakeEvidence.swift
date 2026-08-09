import Foundation

/// One inspectable factor of the awake-evidence model (WG-080). Each is a *weak* signal on its own;
/// only corroboration across factors reaches `.likely`. String-raw so an unknown persisted value
/// fails to decode (#27).
enum AwakeFactor: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Enough steps accrued in the recent window.
    case recentSteps
    /// A sustained continuous movement episode (WG-067) — long enough to be more than a stir.
    case sustainedEpisode
    /// Movement happened recently (recency), not stale minutes ago.
    case recentMovement
    /// The device was interacted with / picked up — an *optional* supporting signal, never decisive.
    case deviceInteraction
}

/// How strongly the evidence suggests the sleeper is awake (WG-080). **Advisory only** — even
/// `.likely` never cancels or suppresses an alarm (#8); it can only *inform* a pre-alarm prompt.
/// String-raw fail-closed (#27).
enum AwakeLikelihood: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Not enough evidence.
    case notEnough
    /// Some evidence, but **not corroborated** — a single weak signal is never conclusive.
    case weak
    /// Multiple corroborating factors — still advisory, still never cancels an alarm.
    case likely
}

/// One factor's contribution to the assessment — whether it fired and the weight it added — so the
/// reasoning is fully **inspectable** (a consumer can show exactly why the evidence read as it did).
struct AwakeFactorContribution: Sendable, Equatable, Hashable, Codable {
    let factor: AwakeFactor
    let present: Bool
    /// The weight this factor adds to the score when present (0 otherwise).
    let weight: Double

    var contribution: Double { present ? weight : 0 }
}

/// The awake-evidence assessment (WG-080): an advisory likelihood, the total score, and the
/// per-factor contributions. Carries **no** action — it is an assessment value, so it structurally
/// cannot suppress an alarm (#8).
struct AwakeEvidence: Sendable, Equatable, Hashable, Codable {
    let likelihood: AwakeLikelihood
    let score: Double
    let contributions: [AwakeFactorContribution]

    /// The factors that actually fired — a convenience over `contributions`.
    var presentFactors: [AwakeFactor] { contributions.filter(\.present).map(\.factor) }
}

/// The raw signals the model weighs (WG-080), derived from motion + an optional device-interaction
/// flag. Kept separate from the model so the derivation (e.g. from `MovementEpisode`s) is testable.
struct AwakeEvidenceInput: Sendable, Equatable, Hashable {
    /// Steps accrued in the recent window.
    let recentStepCount: Int
    /// The longest sustained movement episode's duration (seconds).
    let longestEpisodeDuration: TimeInterval
    /// Seconds since the most recent movement (recency); large / `.infinity` when there was none.
    let secondsSinceLastMovement: TimeInterval
    /// Whether the device was interacted with (the optional supporting signal).
    let deviceInteracted: Bool
}

/// The deterministic awake-evidence model (WG-080). It combines four weak signals — recent steps, a
/// sustained episode, recency, and an optional device interaction — into an advisory `AwakeEvidence`.
/// **No single factor is conclusive**: `Config` clamps every factor weight strictly below
/// `likelyThreshold`, so `.likely` requires corroboration *by construction* (not merely by the
/// default literal). Pure and deterministic; it produces an assessment, never an action — a movement
/// inference alone never cancels an alarm (#8).
///
/// **Known limitation (pinned by `testPassiveTransportReadsAsAwakeKnownLimitation`):** the model has
/// no activity-class or cadence discriminator, so passive transport — a phone accruing pedometer
/// steps in a bag on a moving vehicle — presents recent steps + a sustained episode + recency at
/// once and reads as `.likely`. This is tolerable *only* because the model is advisory: a false
/// `.likely` can surface a pre-alarm prompt but can never suppress an alarm (#8). A later task may
/// add a cadence/activity gate; until then the residual is documented, not hidden.
enum AwakeEvidenceModel {

    /// Tunable factor thresholds + weights. The initializer **clamps every factor weight strictly
    /// below `likelyThreshold`** and routes non-finite / negative inputs to safe defaults, so the
    /// no-single-signal-conclusive property holds for *any* caller-supplied config (mirrors WG-075's
    /// re-clamp-on-construct pattern; fail-closed toward "not awake").
    struct Config: Sendable, Equatable {
        let minRecentSteps: Int
        let minSustainedDuration: TimeInterval
        let recencyWindow: TimeInterval
        let recentStepsWeight: Double
        let sustainedEpisodeWeight: Double
        let recentMovementWeight: Double
        let deviceInteractionWeight: Double
        let weakThreshold: Double
        let likelyThreshold: Double

        init(
            minRecentSteps: Int, minSustainedDuration: TimeInterval, recencyWindow: TimeInterval,
            recentStepsWeight: Double, sustainedEpisodeWeight: Double, recentMovementWeight: Double,
            deviceInteractionWeight: Double, weakThreshold: Double, likelyThreshold: Double
        ) {
            let likely = (likelyThreshold.isFinite && likelyThreshold > 0) ? likelyThreshold : 0.6
            // Strictly below the likely bar → no lone factor can ever reach `.likely`.
            let cap = likely.nextDown
            func weight(_ value: Double) -> Double {
                guard value.isFinite, value > 0 else { return 0 }
                return min(value, cap)
            }
            func nonNegative(_ value: Double, fallback: Double) -> Double {
                (value.isFinite && value >= 0) ? value : fallback
            }
            self.likelyThreshold = likely
            self.weakThreshold = min(nonNegative(weakThreshold, fallback: 0.25), likely)
            self.recentStepsWeight = weight(recentStepsWeight)
            self.sustainedEpisodeWeight = weight(sustainedEpisodeWeight)
            self.recentMovementWeight = weight(recentMovementWeight)
            self.deviceInteractionWeight = weight(deviceInteractionWeight)
            self.minRecentSteps = max(0, minRecentSteps)
            self.minSustainedDuration = nonNegative(minSustainedDuration, fallback: 20)
            self.recencyWindow = nonNegative(recencyWindow, fallback: 300)
        }

        static let `default` = Config(
            minRecentSteps: 15, minSustainedDuration: 20, recencyWindow: 300,
            recentStepsWeight: 0.4, sustainedEpisodeWeight: 0.4, recentMovementWeight: 0.25,
            deviceInteractionWeight: 0.15, weakThreshold: 0.25, likelyThreshold: 0.6)
    }

    static func evaluate(_ input: AwakeEvidenceInput, config: Config = .default) -> AwakeEvidence {
        // Fail-closed sanitisation: a non-finite / negative duration or recency must never *fire* a
        // factor (`.infinity` duration would satisfy `>= minSustainedDuration`; a negative recency
        // would satisfy `<= recencyWindow`). Route both toward "absent".
        let duration =
            (input.longestEpisodeDuration.isFinite && input.longestEpisodeDuration >= 0)
            ? input.longestEpisodeDuration : 0
        let recency =
            input.secondsSinceLastMovement >= 0 ? input.secondsSinceLastMovement : .infinity
        let contributions = [
            AwakeFactorContribution(
                factor: .recentSteps, present: input.recentStepCount >= config.minRecentSteps,
                weight: config.recentStepsWeight),
            AwakeFactorContribution(
                factor: .sustainedEpisode, present: duration >= config.minSustainedDuration,
                weight: config.sustainedEpisodeWeight),
            AwakeFactorContribution(
                factor: .recentMovement, present: recency <= config.recencyWindow,
                weight: config.recentMovementWeight),
            AwakeFactorContribution(
                factor: .deviceInteraction, present: input.deviceInteracted,
                weight: config.deviceInteractionWeight),
        ]
        let score = contributions.reduce(0) { $0 + $1.contribution }
        let likelihood: AwakeLikelihood =
            score >= config.likelyThreshold
            ? .likely : (score >= config.weakThreshold ? .weak : .notEnough)
        return AwakeEvidence(likelihood: likelihood, score: score, contributions: contributions)
    }

    /// Derive the input from movement episodes (WG-067) + an optional device-interaction flag, then
    /// evaluate. `now` supplies recency; a future-dated episode (end after `now`) is dropped from
    /// recency, and the step sum saturates rather than trapping on overflow.
    static func evaluate(
        episodes: [MovementEpisode], deviceInteracted: Bool, now: Date, config: Config = .default
    ) -> AwakeEvidence {
        let recentStepCount = episodes.reduce(0) { accumulated, episode in
            let (sum, overflow) = accumulated.addingReportingOverflow(max(0, episode.stepCount))
            return overflow ? Int.max : sum
        }
        let longestEpisodeDuration = episodes.map(\.duration).max() ?? 0
        let secondsSinceLastMovement =
            episodes.map { now.timeIntervalSince($0.end) }.filter { $0 >= 0 }.min() ?? .infinity
        return evaluate(
            AwakeEvidenceInput(
                recentStepCount: recentStepCount, longestEpisodeDuration: longestEpisodeDuration,
                secondsSinceLastMovement: secondsSinceLastMovement,
                deviceInteracted: deviceInteracted), config: config)
    }
}
