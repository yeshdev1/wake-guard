import Foundation

/// Persists which wake occurrences were satisfied by a **genuine challenge pass** (WG-290) — the
/// commitment lock's failsafe. A recorded pass releases the ring-window lock for *that specific fire
/// instant* (the alarm becomes changeable again through the normal #6 confirmation), while an unsatisfied
/// wake stays locked so the live re-ring chain cannot be deleted out from under it (WG-288/291).
///
/// Both operations are **best-effort and fail-closed**: a write failure means the lock simply holds until
/// the bounded window ends (never a stuck alarm — the window is finite); a read failure reads as
/// "not satisfied" (the lock holds; enforcement is never accidentally released).
protocol SatisfiedWakeStore: Sendable {
    /// Record that `alarmID`'s wake at `fireTime` was satisfied by a valid pass. Idempotent.
    func markSatisfied(alarmID: AlarmID, fireTime: Date) async
    /// Whether the wake at `fireTime` was satisfied. Unknown/error → `false` (the lock holds).
    func isSatisfied(alarmID: AlarmID, fireTime: Date) async -> Bool
}
