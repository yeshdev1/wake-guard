import Foundation

/// The debounced state of an optional monitored region (WG-103). `.unknown` is the **safe default** —
/// used when the rule is disabled or no crossing has settled — so region monitoring never forces a
/// decision without confident data (a critical alarm rings regardless, #8/#9).
enum RegionState: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case inside
    case outside
    case unknown

    /// Fail-closed decode (#27): an unrecognized persisted raw value resolves to `.unknown` — the safe
    /// fallback — never a confident `.inside`/`.outside`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RegionState(rawValue: raw) ?? .unknown
    }
}

/// A raw geofence boundary crossing (WG-103): the device reported it was `.inside` or `.outside` the
/// region at `at` — or `.unknown` when the region signal was lost. These are **noisy** near the
/// boundary — the debouncer, not this event, decides.
struct RegionEvent: Sendable, Equatable {
    let state: RegionState
    let at: Date
}

/// Debounces noisy geofence boundary crossings (WG-103). Folds enter/exit events into the last
/// **stable** state — one that held for at least `dwellTime` before the next crossing (or, for the final
/// event, up to `now`). A flip that reverses before `dwellTime` is boundary noise and never commits, so
/// a device flickering at a region edge doesn't churn the state.
///
/// Robust to adversarial input: events are sorted chronologically (callback order isn't trusted), and
/// any event dated after `now` — e.g. from a backward clock correction — is ignored, since it hasn't
/// happened yet and can neither commit a state nor bound a prior event's dwell. An interleaved
/// `.unknown` (lost signal) is a real boundary that **interrupts** the dwell: it caps the preceding
/// state's measured hold, so confidence must be re-established by a fresh sustained crossing rather than
/// assumed across a gap in the signal. Every path biases toward `.unknown`, the safe fallback.
struct RegionDebouncer: Sendable {
    let dwellTime: TimeInterval

    func stableState(from events: [RegionEvent], now: Date) -> RegionState {
        let ordered = events.filter { $0.at <= now }.sorted { $0.at < $1.at }
        var stable: RegionState = .unknown
        for (index, event) in ordered.enumerated() where event.state != .unknown {
            // The state held until the next crossing (incl. a signal-loss `.unknown`), or until `now`
            // for the final event. Sorting + the future-event filter keep this hold non-negative.
            let heldUntil = index + 1 < ordered.count ? ordered[index + 1].at : now
            if heldUntil.timeIntervalSince(event.at) >= dwellTime {
                stable = event.state
            }
        }
        return stable
    }
}

/// An **optional** region-monitoring rule (WG-103) — e.g. "my home region". **Disabled by default**:
/// region monitoring runs only when the user explicitly opts in. Advisory throughout — a region state
/// never suppresses an alarm, and the safe fallback (`.unknown`) applies whenever the rule is off, so a
/// **critical** alarm always rings regardless of region (#8/#9). Holds no alarm authority.
///
/// Distinct from `AlarmDomain.RegionRule`, which is a **policy** mapping (region → `TravelBehavior`
/// with a mandatory non-region safe fallback); this type is the **detection** mechanic that folds noisy
/// geofence crossings into a debounced state. Different layer, different responsibility.
struct RegionMonitoringRule: Sendable, Equatable, Hashable, Codable {
    let identifier: String
    /// Explicit opt-in — `false` unless the user enables it.
    let isEnabled: Bool
    /// The dwell a boundary crossing must hold to count (WG-103). Clamped to a safe minimum so a
    /// pathological config can't disable debouncing.
    let dwellTime: TimeInterval

    init(identifier: String, isEnabled: Bool = false, dwellTime: TimeInterval = 60) {
        self.identifier = identifier
        self.isEnabled = isEnabled
        self.dwellTime = (dwellTime.isFinite && dwellTime >= 30) ? dwellTime : 60
    }

    /// The debounced state for this rule — or `.unknown` (the **safe fallback**) when the rule is
    /// disabled, so an off-by-default optional rule drives no decision.
    func stableState(from events: [RegionEvent], now: Date) -> RegionState {
        guard isEnabled else { return .unknown }
        return RegionDebouncer(dwellTime: dwellTime).stableState(from: events, now: now)
    }
}
