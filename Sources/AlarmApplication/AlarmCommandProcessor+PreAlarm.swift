import Foundation

/// Pre-alarm prompt response handlers (E05, WG-084+). Kept in an extension so the core command path
/// stays within the type-body budget; all are actor-isolated and share the single
/// adapter-invoking boundary (#2). The keep-original response mutates nothing at all.
extension AlarmCommandProcessor {

    /// The user tapped "Keep alarm" on a pre-alarm prompt (WG-084). Keep changes **nothing** — no
    /// local state, no AlarmKit, no reschedule, not even a read — so the original alarm remains exactly
    /// as scheduled (#7). It records only the acknowledgement (`old`/`new` nil — no mutation to hash).
    /// **Stale-safe by construction**: because it never touches the alarm, a missing / deleted /
    /// already-rung alarm is the same safe no-op — no adapter call, no error surfaced.
    func applyKeepOriginal(_ context: CommandContext) async -> CommandOutcome {
        await appendAudit(
            context, old: nil, new: nil, outcome: .noOp,
            reason: "You kept the alarm; nothing was changed.")
        return .noOp
    }
}
