import Foundation

/// A detected device time-zone change (WG-100) — the **no-GPS** travel signal (the app watches the
/// system time zone, never continuous location). Records the IANA zones (#11), previous → current.
/// Advisory: detecting a change never re-anchors or mutates an alarm on its own — a later task
/// (WG-104/105) decides whether to prompt.
struct TimeZoneChange: Sendable, Equatable, Hashable, Codable {
    let previous: IANATimeZone
    let current: IANATimeZone
}

/// Persists the last-known device IANA time zone across launches (WG-100), so a zone change that
/// happened **while the app was closed** is caught by launch reconciliation. A small, non-critical
/// preference (not alarm state). Implementations must be thread-safe (the system notification may
/// arrive off the main thread).
protocol TimeZoneStateStore: Sendable {
    func lastKnownZone() -> IANATimeZone?
    func setLastKnownZone(_ zone: IANATimeZone)
}

/// Detects a device time-zone change against the last-known zone (WG-100) and persists the new baseline.
/// Pure of clock/notification reads — the caller supplies the observed `current` zone, so the same
/// reducer serves both the live `NSSystemTimeZoneDidChange` path and the launch-reconciliation path.
///
/// - The **first** observation just records a baseline (no change — the app has no prior zone).
/// - A **repeated** observation of the same zone is **idempotent** (no change), so duplicate/coalesced
///   notifications don't produce phantom changes.
/// - A **different** zone — whether from a live notification or a persisted baseline that differs at
///   launch (a change missed while closed) — is reported as a `TimeZoneChange`.
struct TimeZoneChangeDetector: Sendable {
    let store: any TimeZoneStateStore

    func observe(current: IANATimeZone) -> TimeZoneChange? {
        let last = store.lastKnownZone()
        store.setLastKnownZone(current)
        guard let last, last != current else { return nil }
        return TimeZoneChange(previous: last, current: current)
    }
}
