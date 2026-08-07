import Foundation

/// Barometric altitude evidence over a bounded window (WG-066) — **supporting evidence only**. A
/// pressure altimeter weakly corroborates that the sleeper physically changed height (stood up,
/// took the stairs), but it is noisy and drifts with weather/HVAC, so this deliberately has **no
/// "fails a challenge" case**: the worst an absent, flat, or drifting altimeter can do is provide no
/// positive corroboration — it can never weaken or fail a challenge (SCOPE; the `AltitudeSample`
/// doc). String-raw so an unknown persisted value fails to decode (#27).
enum AltitudeEvidence: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// No barometer (or not consulted) — neutral, never a penalty (acceptance: an unavailable
    /// barometer has no negative impact).
    case unavailable
    /// Too few or corrupt samples, or a zero-length window — neutral, no claim.
    case insufficient
    /// No significant vertical change, or only a slow drift — neutral. Drift never corroborates.
    case flat
    /// A fast, significant, sustained vertical change (up *or* down) consistent with the sleeper
    /// moving — the only case that corroborates movement, and only **weakly**. Barometry can't
    /// distinguish a real stand-up from a fast pressure transient (door / HVAC / a nearby elevator),
    /// so a consumer must use this to corroborate independent movement evidence, never to pass a
    /// challenge on its own.
    case significantChange

    /// Whether this evidence weakly corroborates movement. Exactly one case does; every other case
    /// is neutral. There is deliberately no case a consumer treats as "failed", so altimeter
    /// evidence is strictly additive — an absent or drifting barometer never subtracts.
    var corroboratesMovement: Bool { self == .significantChange }
}

/// Infers `AltitudeEvidence` from a window of altitude samples, conservatively (WG-066). The key
/// property: **slow pressure drift never reads as a real move** — a genuine move clears both a real
/// *magnitude* and a real *rate*, while weather/HVAC *drift* moves little over a short window and
/// slowly over a long one, so it clears neither together and stays `.flat`. A *fast step* transient
/// (a slammed door, an HVAC kick, an elevator the sleeper isn't in) can clear both and read as
/// `.significantChange` — barometry alone cannot tell it from a stand-up, which is exactly why this
/// is **weak, supporting-only** evidence: a consumer (WG-067/069) must never pass a challenge on a
/// lone `.significantChange`, only let it corroborate independent accel/pedometer movement. Pure and
/// deterministic; reads no clock and makes no framework calls.
enum AltitudeEvidenceAnalyzer {

    /// Tunable thresholds. Cautious defaults; **calibrate on-device** (WG-066 real-device checklist).
    struct Thresholds: Sendable, Equatable {
        /// Below this many samples → `insufficient`.
        var minSamples: Int
        /// Min |net altitude change| (m) to be a candidate real move — well above sensor noise.
        var minSignificantChange: Double
        /// Min rate of change (m/s). Below this the change is drift, not a real move — the drift
        /// discriminator: weather/HVAC never sustains this rate.
        var minChangeRate: Double

        static let `default` = Thresholds(
            minSamples: 5, minSignificantChange: 0.8, minChangeRate: 0.1)
    }

    static func evaluate(
        _ samples: [AltitudeSample], availability: MotionSourceAvailability,
        thresholds: Thresholds = .default
    ) -> AltitudeEvidence {
        // An unavailable/absent barometer is simply not consulted — neutral, never a penalty.
        guard availability == .available else { return .unavailable }
        guard samples.count >= thresholds.minSamples, let first = samples.first,
            let last = samples.last
        else {
            return .insufficient
        }

        let altitudes = samples.map(\.relativeAltitudeMeters)
        let duration = last.timestamp.timeIntervalSince(first.timestamp)
        guard altitudes.allSatisfy(\.isFinite), duration.isFinite, duration > 0 else {
            return .insufficient
        }

        // Robust endpoints (head/tail median) so a single noisy altitude spike can't manufacture a
        // change (cf. WG-065). Clamp the head/tail windows so they stay **disjoint** even at the
        // minimum sample count — overlapping windows would share the middle sample and silently
        // halve the measured span (WG-066 review S2).
        let endpointCount = min(Self.endpointSamples, altitudes.count / 2)
        let netChange = abs(
            Self.median(altitudes.suffix(endpointCount))
                - Self.median(altitudes.prefix(endpointCount)))
        let rate = netChange / duration

        // A real move clears BOTH magnitude and rate; *slow* drift clears at most one → flat. (A
        // fast step transient also clears both — accepted as weak corroboration only; see the type.)
        guard netChange >= thresholds.minSignificantChange, rate >= thresholds.minChangeRate else {
            return .flat
        }
        return .significantChange
    }

    /// Head/tail sample count for the median endpoints — a true median needs ≥3 to reject one spike.
    private static let endpointSamples = 3

    private static func median(_ values: ArraySlice<Double>) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
