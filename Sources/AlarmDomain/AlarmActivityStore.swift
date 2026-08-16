import Foundation

/// A recorded wake plus its **cached** plain-English narration (WG-299). The narration is generated once
/// (deterministic, optionally rephrased by the on-device model) and stored, so re-opening the history
/// never re-runs the model and the text stays stable.
struct AlarmActivityEntry: Sendable, Equatable, Hashable {
    let activity: AlarmActivity
    /// The cached, user-facing summary — grounded in `activity`'s facts (#32).
    let summary: String
}

/// Persists the on-device wake-activity history (WG-299): one entry per rung alarm's challenge, read back
/// most-recent-first for the "Alarm Activity" section, and pruned by an explicit retention window (#43).
/// Behavioral data, so **on-device only** (#35/#40), **never logged** (#41), and covered by export/delete
/// (#42) and full-erase. Best-effort: a write fault simply drops that one history entry (never an alarm
/// effect — activity is advisory, #8/#9); a read fault yields an empty history.
protocol AlarmActivityStore: Sendable {
    /// Record one wake with its cached summary. Idempotent per (alarm, occurrence instant).
    func record(_ entry: AlarmActivityEntry) async
    /// The most recent entries, newest first, capped at `limit`.
    func recentActivities(limit: Int) async -> [AlarmActivityEntry]
    /// Drop entries older than `cutoff` — the retention sweep (#43).
    func pruneActivities(olderThan cutoff: Date) async
}

/// Records one wake into the activity history (WG-299) — the seam the challenge runtime calls at an
/// outcome. Advisory only: it carries no alarm authority and its failure never affects an alarm (#8/#9).
/// Injected as optional so previews / hermetic tests can omit it.
protocol AlarmActivityRecording: Sendable {
    func record(_ activity: AlarmActivity) async
}
