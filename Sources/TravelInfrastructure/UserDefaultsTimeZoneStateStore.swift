import Foundation

/// Persists the last-known device IANA zone in `UserDefaults` (WG-100) — a small, non-critical
/// preference (not alarm state, so deliberately not in the Core Data store). A stored value that is
/// missing or no longer a valid IANA identifier fails closed to `nil`, so a corrupt preference just
/// re-baselines rather than crashing (#11/#27-style fail-closed).
///
/// `@unchecked Sendable` is justified: `UserDefaults` is documented thread-safe (Apple), it just isn't
/// marked `Sendable` in the SDK, and the stored reference is immutable.
struct UserDefaultsTimeZoneStateStore: TimeZoneStateStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "wg.travel.lastKnownTimeZone"

    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastKnownZone() -> IANATimeZone? {
        guard let identifier = defaults.string(forKey: key) else { return nil }
        return try? IANATimeZone(identifier: identifier)
    }

    func setLastKnownZone(_ zone: IANATimeZone) {
        defaults.set(zone.identifier, forKey: key)
    }
}
