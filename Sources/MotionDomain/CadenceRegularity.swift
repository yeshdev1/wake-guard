import Foundation

/// The verdict of the cadence-regularity / anti-shake defense (WG-070). Only `.plausibleGait`
/// corroborates a real walk; every other case is a rejection reason (a rejection means "not
/// verified", never an authoritative *fail* — the timeout keeps the alarm, #21). String-raw so an
/// unknown value fails to decode (#27).
enum CadenceVerdict: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// The inter-step timing is consistent with a real walk — plausibly paced and naturally varied.
    case plausibleGait
    /// Not enough step intervals to judge cadence (rapid irregular motion *without* sustained
    /// pedometer evidence lands here or in `.implausibleTiming`).
    case tooFewSteps
    /// A step interval falls outside the plausible per-step band (too fast = a shake; too slow = not
    /// continuous walking).
    case implausibleTiming
    /// Inter-step intervals vary too much — erratic motion, i.e. a shake, not a gait.
    case tooErratic
    /// Inter-step intervals are *implausibly* regular (near-zero variation) — a metronomic tap or a
    /// replayed loop, which a human gait never produces.
    case tooRegular

    /// Whether this verdict corroborates a real walk — exactly one case does.
    var corroboratesWalk: Bool { self == .plausibleGait }
}

/// Tunable cadence thresholds (WG-070). Cautious defaults; **on-device calibration is required**
/// (WG-075 study / checklist). The **false-positive risk is real and specific**: a steady treadmill
/// walker (near-constant cadence → `.tooRegular`), a slow or elderly gait slower than
/// `maxStepInterval` (→ `.implausibleTiming`), and a very-regular walker can each be *rejected*. Each
/// is tolerable only because a rejection is non-authoritative (the timeout keeps the alarm) and the
/// **accessible alternative is always available** (#21/#22) — never by narrowing that safety net.
struct CadenceThresholds: Sendable, Equatable, Codable {
    /// Minimum number of step *intervals* needed to judge cadence (a shake burst is short).
    var minimumIntervals: Int
    /// Fastest plausible per-step interval (s) — below this is implausibly fast (a shake).
    var minStepInterval: TimeInterval
    /// Slowest per-step interval (s) for *continuous* walking — above this isn't a sustained gait.
    var maxStepInterval: TimeInterval
    /// Below this coefficient of variation the cadence is implausibly metronomic (tap / replay).
    var minCoefficientOfVariation: Double
    /// Above this coefficient of variation the cadence is erratic (a shake).
    var maxCoefficientOfVariation: Double

    static let `default` = CadenceThresholds(
        minimumIntervals: 8, minStepInterval: 0.25, maxStepInterval: 1.2,
        minCoefficientOfVariation: 0.03, maxCoefficientOfVariation: 0.5)
}

/// Anti-shake / anti-replay cadence defense (WG-070) — the shake/replay discriminator WG-069
/// deferred here. It reconstructs the inter-step interval series from timestamped cumulative step
/// counts (the live pedometer exposes no per-step interval, WG-063) and rejects motion whose cadence
/// isn't a plausible, naturally-varied human gait. **Anti-replay scope:** a segment with no new
/// steps (Δsteps ≤ 0 — a duplicate or reset) contributes no interval, and a *constant-cadence*
/// (metronomic) replay is rejected as `.tooRegular`. A *jittered fabricated* stream (monotonic counts
/// with hand-like variation) is NOT defeated by this statistic — that is the adapter's
/// injection-trust boundary (WG-063), not a cadence property. Pure and deterministic.
enum CadenceRegularity {

    /// Reconstruct the average inter-step interval series (seconds per step) from movement
    /// observations' cumulative step counts. Observations without a step count, and any segment with
    /// no *new* steps (a duplicate/replayed sample or a reset), are skipped — so replays add no
    /// intervals and cannot inflate the cadence signal.
    static func intervals(from observations: [MovementObservation]) -> [Double] {
        let stepped =
            observations
            .compactMap { obs in obs.cumulativeSteps.map { (obs.timestamp, $0) } }
            .filter { $0.0.timeIntervalSince1970.isFinite }
            .sorted { $0.0 < $1.0 }

        var result: [Double] = []
        for (previous, current) in zip(stepped, stepped.dropFirst()) {
            let deltaSteps = current.1 - previous.1
            guard deltaSteps > 0 else { continue }
            let deltaTime = current.0.timeIntervalSince(previous.0)
            guard deltaTime > 0 else { continue }
            result.append(deltaTime / Double(deltaSteps))
        }
        return result
    }

    /// Classify an inter-step interval series (real `secondsSinceLastStep` or reconstructed).
    /// Rejects too-few / out-of-band / erratic / metronomic cadence; only a plausibly-varied,
    /// plausibly-paced series is `.plausibleGait`.
    static func classify(
        intervals: [Double], thresholds: CadenceThresholds = .default
    ) -> CadenceVerdict {
        let valid = intervals.filter { $0.isFinite && $0 > 0 }
        guard valid.count >= thresholds.minimumIntervals else { return .tooFewSteps }
        if valid.contains(where: {
            $0 < thresholds.minStepInterval || $0 > thresholds.maxStepInterval
        }
        ) {
            return .implausibleTiming
        }
        let mean = valid.reduce(0, +) / Double(valid.count)
        guard mean > 0 else { return .implausibleTiming }
        let variance = valid.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(valid.count)
        let coefficientOfVariation = variance.squareRoot() / mean
        if coefficientOfVariation > thresholds.maxCoefficientOfVariation { return .tooErratic }
        if coefficientOfVariation < thresholds.minCoefficientOfVariation { return .tooRegular }
        return .plausibleGait
    }

    /// Reconstruct from observations and classify — the end-to-end anti-shake verdict.
    static func verify(
        _ observations: [MovementObservation], thresholds: CadenceThresholds = .default
    ) -> CadenceVerdict {
        classify(intervals: intervals(from: observations), thresholds: thresholds)
    }

    /// The cadence stats + verdict for an observation series — surfaces the interval count and coefficient
    /// of variation that `classify` decides on, so the anti-shake thresholds can be calibrated from real
    /// device data (WG-075) rather than guessed. Pure; carries no samples.
    static func diagnose(
        _ observations: [MovementObservation], thresholds: CadenceThresholds = .default
    ) -> CadenceDiagnostics {
        let series = intervals(from: observations)
        let valid = series.filter { $0.isFinite && $0 > 0 }
        let mean = valid.isEmpty ? 0 : valid.reduce(0, +) / Double(valid.count)
        var coefficientOfVariation = 0.0
        if !valid.isEmpty, mean > 0 {
            let variance = valid.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(valid.count)
            coefficientOfVariation = variance.squareRoot() / mean
        }
        return CadenceDiagnostics(
            intervalCount: valid.count, meanSecondsPerStep: mean,
            coefficientOfVariation: coefficientOfVariation,
            verdict: classify(intervals: series, thresholds: thresholds))
    }
}

/// A read-only snapshot of the anti-shake cadence stats for a run (WG-075) — the numbers behind the verdict.
struct CadenceDiagnostics: Sendable, Equatable {
    let intervalCount: Int
    let meanSecondsPerStep: Double
    let coefficientOfVariation: Double
    let verdict: CadenceVerdict
}
