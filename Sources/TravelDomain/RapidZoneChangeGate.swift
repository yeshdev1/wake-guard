import Foundation

/// A device time-zone observation tagged with a **monotonic version** and the instant observed (WG-108).
/// In airport/transit, zone changes arrive rapidly and possibly **out of order** (a delayed system
/// notification, a VPN flap); the version lets the *latest reliable* state win regardless of delivery
/// order — a lower version never overrides a higher one. Versions are caller-assigned and monotonic,
/// **unique per logical change** (a re-delivery of the same change reuses its version). Should two
/// observations still collide on the top version, the gate resolves the tie **deterministically** —
/// newest `observedAt`, then `zone.identifier` — never by array/delivery order.
struct VersionedZoneObservation: Sendable, Equatable, Hashable {
    let zone: IANATimeZone
    let version: Int
    let observedAt: Date
}

/// Coalesces rapid device time-zone changes (airport/transit, WG-108) so a transient flip does not spam
/// travel prompts, keeps only the **latest reliable** state (by version), and **defers** a change for an
/// alarm that is about to ring so it is never destabilized. Pure — a reducer over observations plus a
/// guard; it holds **no alarm authority** (it yields a settled zone or a defer decision, never a
/// mutation), and deferral is a safe no-op that leaves the alarm exactly as scheduled (#16/#9).
struct RapidZoneChangeGate: Sendable {
    /// A newly-observed zone must hold at least this long before it is considered **settled** (and thus
    /// prompt-worthy). Suppresses spam from rapid flips. Clamped to a safe minimum so a pathological
    /// config can't disable coalescing.
    let settleDuration: TimeInterval
    /// An alarm within this window of firing (or overdue) is **imminent** — a travel change is deferred,
    /// not applied, so it isn't destabilized. Clamped to a safe minimum.
    let imminentWindow: TimeInterval

    init(settleDuration: TimeInterval = 120, imminentWindow: TimeInterval = 900) {
        let settle = (settleDuration.isFinite && settleDuration >= 30) ? settleDuration : 120
        let imminent = (imminentWindow.isFinite && imminentWindow >= 60) ? imminentWindow : 900
        // Cap at a day so a pathological huge value can't permanently defer every alarm or never settle.
        self.settleDuration = Swift.min(settle, 86_400)
        self.imminentWindow = Swift.min(imminent, 86_400)
    }

    /// The latest reliable zone that has **settled**, or `nil` while things are still changing. It is the
    /// **highest-version** observation's zone (versioning: a stale, out-of-order lower-version observation
    /// never wins), returned only once that observation has held for `settleDuration` — i.e. no newer
    /// observation (a flip) has arrived within the window. Rapid flapping therefore yields `nil` (no
    /// prompt) until it stops. Errs toward suppression — the safe direction for prompt spam.
    ///
    /// Selection is a **total order** — version, then newest `observedAt`, then `zone.identifier` — so the
    /// result is independent of array/delivery order even when two observations collide on the top version
    /// (a delayed re-delivery / flap / launch replay): the latest reliable state wins deterministically.
    func settledZone(from observations: [VersionedZoneObservation], now: Date) -> IANATimeZone? {
        let latest = observations.max {
            ($0.version, $0.observedAt, $0.zone.identifier)
                < ($1.version, $1.observedAt, $1.zone.identifier)
        }
        guard let latest, now.timeIntervalSince(latest.observedAt) >= settleDuration else {
            return nil
        }
        return latest.zone
    }

    /// Whether a travel change must be **deferred** for an alarm ringing at `nextRing` — `true` when the
    /// ring is within `imminentWindow` (or already due/overdue), so an alarm close to firing is not
    /// destabilized by a transient zone change (#16/#9). A safe no-op: deferral leaves the alarm exactly
    /// as scheduled; the change can be reconsidered after it rings. `nil` (no scheduled ring) → `false`.
    func shouldDeferForImminentAlarm(nextRing: Date?, now: Date) -> Bool {
        guard let nextRing else { return false }
        return nextRing.timeIntervalSince(now) <= imminentWindow
    }
}
