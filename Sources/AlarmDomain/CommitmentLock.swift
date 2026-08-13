import Foundation

/// Configuration for the commitment lock (WG-288): how long before the fire instant a critical
/// wake-challenge alarm becomes committed, and how long after an unsatisfied fire the lock persists (the
/// relentless-ring window — sourced from `RearmConfiguration` so the two never drift). Values are clamped
/// non-negative. The window is a product constant, not user-configurable below the floor.
struct CommitmentLockConfiguration: Sendable, Equatable {
    /// The alarm is committed from `fire − window` (default 60 minutes, WG-293 decision 2026-08-13).
    let window: TimeInterval
    /// After an unsatisfied fire the lock holds for the bounded ring window (default: the re-arm chain's
    /// total span), so the alarm cannot be deleted mid-ring to silence the chain.
    let ringBound: TimeInterval

    init(
        window: TimeInterval = 3600,
        ringBound: TimeInterval = RearmConfiguration.default.totalWindow
    ) {
        self.window = max(0, window)
        self.ringBound = max(0, ringBound)
    }

    static let `default` = CommitmentLockConfiguration()
}

/// The pure commitment-lock rule (WG-288/293, human-approved 2026-08-13 — amends invariant #6): a
/// **critical + wake-challenge + enabled** alarm is locked from **60 minutes before its fire instant**
/// until its wake is satisfied or the bounded ring window ends. While locked, the policy engine rejects
/// every destructive command outright — confirmation is no longer sufficient. Deterministic; the caller
/// supplies `now` (injected clock), the engine-resolved `nextFireTime`, and — once pending-wake persistence
/// exists (WG-290) — the unsatisfied fire instant, which extends the lock through the ring window even
/// though the *next* occurrence has already rolled to tomorrow.
enum CommitmentLock {
    static func isLocked(
        alarm: Alarm,
        nextFireTime: Date?,
        pendingUnsatisfiedFireTime: Date? = nil,
        now: Date,
        config: CommitmentLockConfiguration = .default
    ) -> Bool {
        guard alarm.criticality == .critical, alarm.challengePolicy.isRequired, alarm.isEnabled
        else { return false }
        // Ring window: an unsatisfied fire keeps the alarm committed while the chain is live, so it
        // cannot be deleted mid-ring to silence the re-rings (the next occurrence is already tomorrow).
        if let pending = pendingUnsatisfiedFireTime, now >= pending,
            now < pending.addingTimeInterval(config.ringBound)
        {
            return true
        }
        // Pre-fire window: committed once the fire instant is `window` away or closer. A past or absent
        // fire instant is not a pre-window lock (the pending branch above owns post-fire time; a clock
        // jump cannot conjure a lock).
        guard let fire = nextFireTime else { return false }
        let untilFire = fire.timeIntervalSince(now)
        return untilFire >= 0 && untilFire <= config.window
    }
}
