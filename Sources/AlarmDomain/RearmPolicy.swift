import Foundation

/// Configuration for the challenge re-arm loop (WG-283): how often a not-passed **critical** wake challenge
/// re-fires, and the **cap** that bounds it. The cap is a safety requirement — an alarm a user cannot end is
/// abuse and dangerous in an emergency (WG-285 ADR). Defaults: every 2 minutes, up to 15 times (~30 min),
/// then stop. Values are clamped non-negative so a pathological config can't produce a negative delay or a
/// negative cap.
struct RearmConfiguration: Sendable, Equatable {
    /// Delay between a stop-without-pass and the next ring.
    let interval: TimeInterval
    /// Maximum number of re-arms before the loop stops for good — the safety cap.
    let maxAttempts: Int

    init(interval: TimeInterval = 120, maxAttempts: Int = 15) {
        self.interval = max(0, interval)
        self.maxAttempts = max(0, maxAttempts)
    }

    /// Every 2 minutes, up to 15 cycles (~30 min), then stop (WG-283 decision 1).
    static let `default` = RearmConfiguration()

    /// The chain's total span — how long a stopped-without-pass alarm keeps coming back. The commitment
    /// lock's ring window derives from this, so the lock and the chain can never disagree (WG-288).
    var totalWindow: TimeInterval { interval * Double(maxAttempts) }
}

/// A **critical** alarm whose ring has not yet been satisfied by a passed challenge (WG-283). Tracked so a
/// stop-without-pass can re-fire the alarm until the user actually walks (or the cap is reached). Only
/// critical alarms are tracked (decision 2); the wiring layer never creates one for a standard alarm.
struct PendingChallenge: Sendable, Equatable {
    let alarmID: AlarmID
    /// The original scheduled fire instant — for audit/telemetry; the cap math does not depend on it.
    let originalFireTime: Date
    /// How many times the alarm has already been re-armed for this wake.
    var attempts: Int

    init(alarmID: AlarmID, originalFireTime: Date, attempts: Int = 0) {
        self.alarmID = alarmID
        self.originalFireTime = originalFireTime
        self.attempts = attempts
    }
}

/// The re-arm decision (WG-283): re-fire at a bounded future instant, or stop because the cap is reached.
enum RearmDecision: Sendable, Equatable {
    case rearm(at: Date)
    case stop
}

/// The **pure** re-arm policy (WG-283) — no Apple frameworks, no clock of its own. Given the current time and
/// a pending challenge, decide whether to re-arm the critical alarm (and when) or to stop because the bounded
/// cap is reached. Deterministic; the caller supplies `now` from the injected `Clock`.
///
/// Scope boundary: the **critical-only** gating (decision 2) and the **stop-without-pass-only, never on
/// background** trigger (decision 4) live in the wiring layer (WG-284). This spec owns only the interval/cap
/// math, so the safety cap has one readable, unit-tested definition.
enum RearmPolicy {
    static func next(
        after now: Date, pending: PendingChallenge, config: RearmConfiguration = .default
    ) -> RearmDecision {
        // The cap is the safety bound — at or past it the loop stops, so the alarm is never un-endable
        // (WG-285). Below it, re-fire one interval out.
        guard pending.attempts < config.maxAttempts else { return .stop }
        return .rearm(at: now.addingTimeInterval(config.interval))
    }
}
