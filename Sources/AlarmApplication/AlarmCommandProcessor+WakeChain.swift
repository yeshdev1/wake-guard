import Foundation

/// Wake-chain hooks (WG-291): keep the pre-scheduled re-ring family in step with the main occurrence.
/// Chain scheduling is deliberately **outbox-free** — every member has a deterministic per-(parent,
/// occurrence, index) id, so a retried schedule replaces itself (idempotent) and a crash costs at most
/// enforcement depth, never the main alarm (#10). Everything here is best-effort: a failed member weakens
/// the chain, never the alarm; stragglers are reaped (or re-placed) by reconciliation (WG-029).
extension AlarmCommandProcessor {

    /// Place (or refresh) the re-ring family behind a just-scheduled main occurrence. No-op unless the
    /// alarm is critical with a required challenge (WG-293 scope guard — `WakeChain.requests` gates).
    func syncWakeChain(for alarm: Alarm, occurrence: Date, context: CommandContext) async {
        let entries = WakeChain.requests(for: alarm, occurrence: occurrence)
        guard !entries.isEmpty else { return }
        var placed = 0
        for entry in entries {
            do {
                try await alarmManager.schedule(entry)
                placed += 1
            } catch { continue }
        }
        await appendAudit(
            context, old: nil, new: nil, outcome: placed == entries.count ? .succeeded : .failed,
            reason: placed == entries.count
                ? "Wake-up re-rings placed behind the alarm."
                : "Some wake-up re-rings couldn’t be placed; the alarm itself is unaffected.")
    }

    /// Remove the family tied to the alarm's next occurrence — used when the alarm is disabled or
    /// deleted (only possible outside the commitment lock). The engine deliberately ignores `isEnabled`,
    /// so the occurrence is still computable for a just-disabled alarm. Silent: the disable/delete that
    /// triggered it is already audited; a missed member reaps as an extra (WG-029).
    func cancelWakeChain(for alarm: Alarm) async {
        guard
            let occurrence = engine.nextOccurrence(
                for: alarm, after: clock.now, deviceTimeZone: deviceTimeZone())
        else { return }
        for id in WakeChain.memberIDs(for: alarm, occurrence: occurrence) {
            try? await alarmManager.cancel(alarmID: id)
        }
    }

    /// After a valid pass, silence the whole live family: stop whichever member is alerting and cancel
    /// the scheduled remainder, so the wake goes fully quiet. Idempotent + best-effort; stop-vs-cancel
    /// behaviour on an alerting member is device-verified (WG-294). No-op when no occurrence fired within
    /// the ring window (a rehearsal pass, or a standard alarm).
    func sweepWakeChain(afterPassOf alarm: Alarm, context: CommandContext) async {
        guard
            let fired = WakeChain.firedOccurrence(
                for: alarm, now: clock.now, deviceTimeZone: deviceTimeZone())
        else { return }
        // Record the satisfied wake FIRST (WG-290) — the commitment lock's failsafe releases even if a
        // member stop below fails; best-effort, and a write fault just leaves the bounded lock in place.
        await satisfiedWakes?.markSatisfied(alarmID: alarm.id, fireTime: fired)
        for id in WakeChain.memberIDs(for: alarm, occurrence: fired) {
            try? await alarmManager.stopRing(alarmID: id)
            try? await alarmManager.cancel(alarmID: id)
        }
        await appendAudit(
            context, old: nil, new: nil, outcome: .succeeded,
            reason: "Wake-up re-rings cleared after the pass.")
    }
}
