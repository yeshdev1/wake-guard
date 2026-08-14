import Foundation

/// Applies an authorized `AlarmCommand` transactionally to local state and AlarmKit via the
/// outbox/reconciliation pattern (WG-027) — the **single command boundary** and the only invoker of
/// `AlarmManagerAdapter` (#2). Per command: authorize (#3, a rejection mutates nothing) → persist
/// local first (#10) → audit (#46) → sync to AlarmKit, the outbox bracketing the external call for
/// crash/uncertain recovery (#10; re-arming is reconciliation's, WG-029).
actor AlarmCommandProcessor {
    private let policy: any AlarmPolicyEngine
    // Internal (not private): the reconcile + wake-chain extensions live in their own files (file-length
    // budget) and share the actor's collaborators; the actor boundary still serializes access (#2).
    let alarms: any AlarmRepository
    private let audit: any AuditRepository
    private let outbox: any OutboxRepository
    let alarmManager: any AlarmManagerAdapter
    let clock: any WallClock
    private let ids: any IdentifierGenerator
    let deviceTimeZone: @Sendable () -> TimeZone
    /// Records satisfied wakes so the commitment lock's failsafe can release post-pass (WG-290). Nil in
    /// graphs that don't wire it — the lock then simply holds for the bounded window (fail-closed).
    let satisfiedWakes: (any SatisfiedWakeStore)?
    let engine = AlarmSchedulingEngine()
    let reconciler = AlarmReconciler()

    init(
        policy: any AlarmPolicyEngine,
        alarms: any AlarmRepository,
        audit: any AuditRepository,
        outbox: any OutboxRepository,
        alarmManager: any AlarmManagerAdapter,
        clock: any WallClock,
        ids: any IdentifierGenerator,
        deviceTimeZone: @escaping @Sendable () -> TimeZone = { .current },
        satisfiedWakes: (any SatisfiedWakeStore)? = nil
    ) {
        self.policy = policy
        self.alarms = alarms
        self.audit = audit
        self.outbox = outbox
        self.alarmManager = alarmManager
        self.clock = clock
        self.ids = ids
        self.deviceTimeZone = deviceTimeZone
        self.satisfiedWakes = satisfiedWakes
    }

    /// Who/what/where of a command in flight — internal so the pre-alarm handler extension shares it.
    struct CommandContext: Sendable {
        let command: AlarmCommand
        let actor: AuditActor
        let source: CommandSource
    }

    /// Authorize, then apply. Every command is authorized (#3) and audited (#46); `userConfirmed` is
    /// required by the policy engine to cancel / delay / weaken a critical or imminent alarm (#6).
    func process(
        _ command: AlarmCommand, from source: CommandSource, by actor: AuditActor,
        userConfirmed: Bool = false
    ) async -> CommandOutcome {
        let context = CommandContext(command: command, actor: actor, source: source)
        // Authorize first. A `.rejected` or `.needsConfirmation` must NOT fall through to
        // apply — the exhaustive switch guarantees a gated command can never mutate state.
        switch await policy.authorize(command, from: source, userConfirmed: userConfirmed) {
        case .authorized:
            break
        case .rejected(let reason):
            await appendAudit(context, old: nil, new: nil, outcome: .rejected, reason: reason)
            return .rejected(reason: reason)
        case .needsConfirmation(let reason):
            // Policy withheld a destructive change pending confirmation (#6); audit the gate, then
            // surface it distinctly so the UI can prompt and re-submit (no mutation).
            await appendAudit(context, old: nil, new: nil, outcome: .rejected, reason: reason)
            return .needsConfirmation(reason: reason)
        }
        return await apply(command, context: context)
    }

    /// Dispatch an authorized command to its handler (kept separate so `process` stays within budget).
    private func apply(_ command: AlarmCommand, context: CommandContext) async -> CommandOutcome {
        switch command {
        case .create(let alarm):
            return await applyMutation(context, mutated: alarm, prior: nil)
        case .update(let alarm):
            let prior = try? await alarms.alarm(id: alarm.id)
            return await applyMutation(context, mutated: alarm, prior: prior)
        case .enable:
            return await applyEnable(context, enabled: true)
        case .disable:
            return await applyEnable(context, enabled: false)
        case .delete:
            return await applyDelete(context)
        case .cancelOccurrence(_, let fireTime):
            return await applyCancelOccurrence(context, fireTime: fireTime)
        case .snooze, .rescheduleOccurrence:
            // Occurrence-level (WG-027 follow-on): surface `.unsupported`, never a silent `.noOp`.
            let reason = "This action isn't available yet; the alarm is unchanged."
            await appendAudit(context, old: nil, new: nil, outcome: .noOp, reason: reason)
            return .unsupported(reason: reason)
        case .markChallengePassed:
            return await applyChallengePassed(context)
        case .keepOriginal:
            return await applyKeepOriginal(context)
        default:
            // reconcile / recover (WG-029): audited here; not applying fails safe (state preserved).
            await appendAudit(
                context, old: nil, new: nil, outcome: .noOp,
                reason: "Accepted; applied by another subsystem.")
            return .noOp
        }
    }

    /// Turn off only *today's* occurrence (WG-085): skip this instant, keep the alarm enabled so the
    /// next recurrence rings. A missing alarm / non-upcoming fireTime no-ops; #6-gated in `authorize`.
    private func applyCancelOccurrence(_ context: CommandContext, fireTime: Date) async
        -> CommandOutcome
    {
        guard var alarm = try? await alarms.alarm(id: context.command.alarmID), fireTime > clock.now
        else {
            await appendAudit(
                context, old: nil, new: nil, outcome: .noOp,
                reason: "That alarm occurrence isn't upcoming; nothing changed.")
            return .noOp
        }
        let prior = alarm
        alarm.skippedOccurrences = alarm.skippedOccurrences.filter { $0 > clock.now }
        alarm.skippedOccurrences.insert(fireTime)
        alarm.revision += 1
        alarm.updatedAt = clock.now
        return await applyMutation(context, mutated: alarm, prior: prior)
    }

    private func applyEnable(_ context: CommandContext, enabled: Bool) async -> CommandOutcome {
        let id = context.command.alarmID
        guard var alarm = try? await alarms.alarm(id: id) else {
            await appendAudit(
                context, old: nil, new: nil, outcome: .failed,
                reason: "The alarm no longer exists.")
            return .failed(reason: "The alarm no longer exists.")
        }
        guard alarm.isEnabled != enabled else { return .noOp }
        let prior = alarm
        alarm.isEnabled = enabled
        alarm.revision += 1
        alarm.updatedAt = clock.now
        return await applyMutation(context, mutated: alarm, prior: prior)
    }

    /// Delete the alarm: drop local state first (#10), audit, then a best-effort system cancel via the
    /// outbox. The local delete is the outcome — a failed cancel leaves at most an "extra" system alarm
    /// (a spurious ring, never a missed one; WG-029 reaps it), so delete-then-cancel, never the reverse.
    private func applyDelete(_ context: CommandContext) async -> CommandOutcome {
        let id = context.command.alarmID
        guard let alarm = try? await alarms.alarm(id: id) else { return .noOp }  // already gone
        do {
            try await alarms.deleteAlarm(id: id)
        } catch {
            let reason = Self.saveFailureReason(for: error)
            await appendAudit(
                context, old: Self.hash(alarm), new: nil, outcome: .failed, reason: reason)
            return .failed(reason: reason)
        }
        await appendAudit(
            context, old: Self.hash(alarm), new: nil, outcome: .succeeded, reason: "Alarm deleted.")
        // The system cancel's outcome must not downgrade the delete — the local record is already gone.
        let key = Self.outboxKey(id, alarm.revision, "cancel", nil)
        _ = await runExternal(key, context.command) {
            try await self.alarmManager.cancel(alarmID: id)
        }
        await cancelWakeChain(for: alarm)  // a deleted alarm leaves no re-rings behind (WG-291)
        return .applied
    }

    /// Persist the mutated alarm (source of truth first, #10), audit it (#46), then
    /// sync to AlarmKit: schedule the next occurrence if enabled, else cancel.
    private func applyMutation(
        _ context: CommandContext, mutated alarm: Alarm, prior: Alarm?
    ) async -> CommandOutcome {
        do {
            try await alarms.save(alarm)
        } catch {
            let reason = Self.saveFailureReason(for: error)
            await appendAudit(
                context, old: prior.map(Self.hash), new: Self.hash(alarm), outcome: .failed,
                reason: reason)
            return .failed(reason: reason)
        }
        await appendAudit(
            context, old: prior.map(Self.hash), new: Self.hash(alarm), outcome: .succeeded,
            reason: alarm.isEnabled ? "Alarm saved." : "Alarm disabled.")

        if alarm.isEnabled,
            let occurrence = engine.nextOccurrence(
                for: alarm, after: clock.now, deviceTimeZone: deviceTimeZone())
        {
            let request = AlarmScheduleRequest(alarm: alarm, fireTime: occurrence)
            let key = Self.outboxKey(alarm.id, alarm.revision, "schedule", occurrence)
            let outcome = await runExternal(key, context.command) {
                try await self.alarmManager.schedule(request)
            }
            // The main occurrence placed → retire the PRIOR occurrence's family (an edit moves the fire
            // instant; the old members would otherwise ring headless, WG-295 D3a), then place the new
            // family behind it (WG-291; no-op unless critical + challenge).
            if case .applied = outcome {
                if let prior { await cancelWakeChain(for: prior) }
                await syncWakeChain(for: alarm, occurrence: occurrence, context: context)
            }
            return outcome
        }
        let key = Self.outboxKey(alarm.id, alarm.revision, "cancel", nil)
        let outcome = await runExternal(key, context.command) {
            try await self.alarmManager.cancel(alarmID: alarm.id)
        }
        // A disabled alarm leaves no re-rings behind — unconditionally (WG-295 D5): an `.uncertain`
        // main-cancel must not strand 15 scheduled members; cancel of an absent id is a no-op.
        await cancelWakeChain(for: alarm)
        return outcome
    }

    /// The outbox brackets the external call: `enqueue` dedups on the key; an `applied` entry is done
    /// (idempotent), an exhausted retry / concurrent owner skips the adapter; a stranded entry is
    /// recovered by reconciliation (#10; WG-029). Internal: the wake-chain extension's pass path uses it.
    func runExternal(
        _ key: String, _ command: AlarmCommand, _ external: () async throws -> Void
    ) async -> CommandOutcome {
        try? await outbox.enqueue(makeEntry(command, key: key))
        guard let entry = try? await outbox.entry(idempotencyKey: key) else {
            return await callExternal(external, entryID: nil)
        }
        if entry.status == .applied { return .applied }
        do {
            try await outbox.markInProgress(entry.id)
        } catch let error as OutboxRepositoryError {
            if case .retryLimitExceeded = error {
                return .failed(reason: "The alarm could not be updated in the system.")
            }
            return .uncertain  // a concurrent owner / resolved entry — reconcile.
        } catch {
            return .uncertain
        }
        return await callExternal(external, entryID: entry.id)
    }

    private func callExternal(
        _ external: () async throws -> Void, entryID: OutboxEntryID?
    ) async -> CommandOutcome {
        do {
            try await external()
            if let entryID { try? await outbox.markApplied(entryID) }
            return .applied
        } catch AlarmManagerError.uncertain, AlarmManagerError.notAuthorized, is CancellationError {
            // All reconcile-later, never a hard failure (#10): `.uncertain` — or a cancelled call — may
            // already have applied; `.notAuthorized` is a user-recoverable deferral (the authorization
            // banner drives the grant; reconciliation places it). The alarm is saved locally either way.
            if let entryID { try? await outbox.markUncertain(entryID) }
            return .uncertain
        } catch {
            let reason = Self.reason(for: error)
            if let entryID { try? await outbox.markFailed(entryID, reason: reason) }
            return .failed(reason: reason)
        }
    }

    private func makeEntry(_ command: AlarmCommand, key: String) -> OutboxEntry {
        OutboxEntry(
            id: OutboxEntryID(ids.next()), command: command, idempotencyKey: key,
            status: .pending, createdAt: clock.now, attempts: 0, lastFailureReason: nil)
    }

    func appendAudit(
        _ context: CommandContext, old: String?, new: String?, outcome: Outcome, reason: String
    ) async {
        // Best-effort: the alarm (already persisted) is the source of truth, so a rare
        // audit-append failure does not fail the command. (An audit gap is not yet
        // repaired at launch — a state-vs-audit backfill is a follow-up.)
        let event = AuditEvent(
            id: AuditEventID(ids.next()), actor: context.actor, command: context.command,
            oldStateHash: old, newStateHash: new, timestamp: clock.now, source: context.source,
            outcome: outcome, correlationID: CorrelationID(ids.next()), userVisibleReason: reason)
        try? await audit.append(event)
    }

}
