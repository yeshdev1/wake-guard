import Foundation

/// Location authorization, mirrored into the domain so travel logic stays framework-independent
/// (the Core Location `CLAuthorizationStatus` is mapped at the adapter boundary, WG-102).
enum LocationAuthorizationStatus: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case notDetermined
    case restricted
    case denied
    case authorizedWhenInUse
    case authorizedAlways

    /// Whether significant-location monitoring can run. `authorizedAlways` additionally allows delivery
    /// while the app is backgrounded; `authorizedWhenInUse` covers the foreground case. Denied /
    /// restricted / notDetermined cannot monitor — and travel detection then relies on the system
    /// time-zone observer alone (WG-100), which does not need location.
    var canMonitor: Bool { self == .authorizedWhenInUse || self == .authorizedAlways }
}

/// A **coarse, low-power** source of significant-location changes (WG-102). It reports only *whether/when*
/// the device meaningfully moved (a timestamp) — **never coordinates** (#41) — and is backed only by
/// Core Location's significant-location-change monitoring, **never continuous GPS**. Optional: a
/// denied/unavailable source reports no change, and travel detection degrades gracefully to the
/// time-zone observer (WG-100), never breaking.
protocol SignificantLocationSource: Sendable {
    func authorizationStatus() async -> LocationAuthorizationStatus
    /// The timestamp of the most recent significant-location change that passed the staleness filter, or
    /// `nil` (none observed, or location unavailable/denied). Coarse — no coordinates.
    func lastSignificantChange() async -> Date?
}

/// Decides whether a significant-location sample is recent enough to trust as a *fresh* move (WG-102).
/// Core Location frequently delivers a **cached** location first, so a sample older than `maxAge` — or
/// dated in the future (a clock glitch) — is rejected. Pure; `now` is injected.
enum SignificantLocationFilter {
    /// A conservative freshness window: significant-location changes are coarse and infrequent, so a
    /// few minutes is ample, and anything older is treated as a cached/stale sample.
    static let defaultMaxAge: TimeInterval = 300

    static func isFresh(_ timestamp: Date, now: Date, maxAge: TimeInterval = defaultMaxAge) -> Bool
    {
        let age = now.timeIntervalSince(timestamp)
        return age >= 0 && age <= maxAge
    }
}
