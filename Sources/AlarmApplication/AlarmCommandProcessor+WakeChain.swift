import Foundation

/// Wake-chain hooks (WG-291/295): keep the pre-scheduled re-ring family in step with the main occurrence.
/// Chain scheduling is deliberately **outbox-free** — every member has a deterministic per-(parent,
/// occurrence, index) id, so a retried schedule replaces itself (idempotent) and a crash costs at most
/// enforcement depth, never the main alarm (#10). Everything here is best-effort: a failed member weakens
/// the chain, never the alarm; stragglers are reaped (or re-placed) by reconciliation (WG-029).
extension AlarmCommandProcessor {

    /// Cleanup callers look back this much past the ring window: the last member starts alerting exactly
    /// at the window's edge, and a pass/delete during (or shortly after) its alert must still resolve the
    /// fired occurrence (WG-295 D3d). The commitment lock does NOT use this slack.
    static let wakeSweepSlack: TimeInterval = 900

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

    /// Remove the alarm's re-ring families — **both** the next occurrence's and, if a wake fired within
    /// the (slack-widened) ring window, the fired occurrence's (WG-295 D4: a post-fire delete/disable
    /// must silence the live family too, not just tomorrow's). The enabled-probe makes the fired lookup
    /// work for a just-disabled alarm. Best-effort; a missed member reaps as an extra (WG-029).
    func cancelWakeChain(for alarm: Alarm) async {
        if let occurrence = engine.nextOccurrence(
            for: alarm, after: clock.now, deviceTimeZone: deviceTimeZone())
        {
            for id in WakeChain.memberIDs(for: alarm, occurrence: occurrence) {
                try? await alarmManager.cancel(alarmID: id)
            }
        }
        var probe = alarm
        probe.isEnabled = true
        if let fired = WakeChain.firedOccurrence(
            for: probe, now: clock.now, deviceTimeZone: deviceTimeZone(),
            slack: Self.wakeSweepSlack)
        {
            for id in WakeChain.memberIDs(for: probe, occurrence: fired) {
                try? await alarmManager.stopRing(alarmID: id)
                try? await alarmManager.cancel(alarmID: id)
            }
        }
    }

    /// After a valid pass, silence the whole live family: stop whichever member is alerting and cancel
    /// the scheduled remainder, so the wake goes fully quiet. Idempotent + best-effort; stop-vs-cancel
    /// behaviour on an alerting member is device-verified (WG-294). No-op when no occurrence fired within
    /// the slack-widened ring window (a rehearsal pass, or a standard alarm).
    func sweepWakeChain(afterPassOf alarm: Alarm, context: CommandContext) async {
        guard
            let fired = WakeChain.firedOccurrence(
                for: alarm, now: clock.now, deviceTimeZone: deviceTimeZone(),
                slack: Self.wakeSweepSlack)
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

    /// A valid challenge pass (WG-073) stops the ringing alarm (#24) via the outbox — racing / duplicate
    /// passes dedup within one wake (adapter called at most once), audited (#46) — then sweeps the
    /// re-ring family silent and arms the next occurrence. Lives here (not the actor's main file) because
    /// the pass IS a wake-chain operation; dispatched from `apply` (type-body budget, WG-295).
    func applyChallengePassed(_ context: CommandContext) async -> CommandOutcome {
        let id = context.command.alarmID
        guard let alarm = try? await alarms.alarm(id: id) else {
            await appendAudit(
                context, old: nil, new: nil, outcome: .noOp, reason: "The alarm no longer exists.")
            return .noOp
        }
        // The key carries the fired occurrence (WG-295 D1): without it, one pass marked the key
        // `.applied` forever (same revision), so every LATER wake's pass silently skipped the adapter —
        // the ring was never stopped again. Rehearsal passes (no fired occurrence) key on `now`.
        let fired = WakeChain.firedOccurrence(
            for: alarm, now: clock.now, deviceTimeZone: deviceTimeZone(),
            slack: Self.wakeSweepSlack)
        let key = Self.outboxKey(id, alarm.revision, "stopRing", fired ?? clock.now)
        let outcome = await runExternal(key, context.command) {
            try await self.alarmManager.stopRing(alarmID: id)
        }
        switch outcome {
        case .uncertain:
            // Outcome unknown — audit `.failed`, not "stopped"; a still-ringing alarm re-completes.
            await appendAudit(
                context, old: nil, new: nil, outcome: .failed,
                reason: "Stop requested after a valid pass; outcome unknown.")
        case .failed(let reason):
            await appendAudit(context, old: nil, new: nil, outcome: .failed, reason: reason)
        default:
            await appendAudit(
                context, old: nil, new: nil, outcome: .succeeded,
                reason: "Alarm stopped after a valid challenge pass.")
        }
        // Silence the whole re-ring family — a pass ends the wake, not just one member — then arm the
        // next occurrence (WG-295 D2: the reconciler defers the parent while a ring window is live, so
        // the pass is when tomorrow's wake gets scheduled).
        await sweepWakeChain(afterPassOf: alarm, context: context)
        await rearmNextWake(for: alarm, context: context)
        return outcome
    }

    /// After a satisfied wake, arm the **next** occurrence (main + chain) right away (WG-295 D2): the
    /// reconciler deliberately keeps hands off the parent while a ring window is live (so it can never
    /// replace an alerting alarm), which makes the pass the moment tomorrow's wake gets scheduled — safe
    /// here, because the pass just silenced this wake. Best-effort; reconcile heals a miss post-window.
    func rearmNextWake(for alarm: Alarm, context: CommandContext) async {
        guard alarm.isEnabled,
            let next = engine.nextOccurrence(
                for: alarm, after: clock.now, deviceTimeZone: deviceTimeZone())
        else { return }
        try? await alarmManager.schedule(AlarmScheduleRequest(alarm: alarm, fireTime: next))
        await syncWakeChain(for: alarm, occurrence: next, context: context)
    }
}
