import Foundation

/// The idempotency key for a pre-alarm prompt (WG-089): a specific alarm's specific occurrence. A
/// prompt is surfaced **at most once per key**, whether the trigger is the background opportunity
/// (WG-088) or the foreground fallback — so an app launch after a background prompt does not
/// re-prompt.
struct PreAlarmPromptKey: Sendable, Equatable, Hashable {
    let alarmID: AlarmID
    /// The occurrence the prompt is about (the alarm's upcoming fire time).
    let occurrence: Date

    /// Stable string form. The occurrence is truncated to a **whole second** (occurrences are
    /// second-aligned) so the key survives `Date`'s JSON float round-trip — kept as a `Double` (never
    /// converted to `Int`, which would trap on a finite-but-out-of-`Int`-range instant like
    /// `.distantFuture`), mirroring the WG-085 skip-match convention. A non-finite instant maps to `0`.
    var identifier: String {
        let seconds = occurrence.timeIntervalSince1970
        let wholeSecond = seconds.isFinite ? seconds.rounded(.towardZero) : 0
        return "\(alarmID.rawValue.uuidString):\(wholeSecond)"
    }
}

/// Records which pre-alarm prompts have already been surfaced, so a prompt shows **at most once** per
/// (alarm, occurrence) (WG-089). The background opportunity and the foreground fallback both `claim`
/// before surfacing; the loser suppresses. Persisted, so the de-dup survives app relaunch. Holds no
/// alarm authority — it never changes an alarm (#7/#8).
protocol PreAlarmPromptLedger: Sendable {
    /// Atomically claim the right to surface this prompt: `true` the first time (the caller should
    /// surface), `false` if it was already claimed (suppress the duplicate). `now` stamps the claim
    /// for retention. Fail-closed: an implementation that cannot record the claim returns `false`
    /// (suppress) rather than risk a duplicate prompt — the alarm is unaffected either way.
    func claim(_ key: PreAlarmPromptKey, at now: Date) async -> Bool
}
