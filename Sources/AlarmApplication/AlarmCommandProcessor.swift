import Foundation

/// Applies an authorized `AlarmCommand` transactionally to local state and AlarmKit via the
/// outbox/reconciliation pattern (WG-027; ARCHITECTURE §6) — the **single command boundary**
/// and the only invoker of `AlarmManagerAdapter` (#2). Per command: authorize (#3, a rejection
/// mutates nothing) → persist local first (source of truth, #10) → audit (#46) → sync to
/// AlarmKit, the outbox bracketing the external call so a crash/uncertain outcome is recoverable
/// (#10; re-arming + stranded-entry recovery are reconciliation's, WG-029). Strict no-interleave
/// serialization is a follow-up (the actor yields at each `await`; the revision guard prevents a
/// lost update). The audit records the *local* mutation; the external outcome lives in the outbox.
actor AlarmCommandProcessor {
    private let policy: any AlarmPolicyEngine
    private let alarms: any AlarmRepository
    private let audit: any AuditRepository
    private let outbox: any OutboxRepository
    private let alarmManager: any AlarmManagerAdapter
    private let clock: any WallClock
    private let ids: any IdentifierGenerator
    private let deviceTimeZone: @Sendable () -> TimeZone
    private let engine = AlarmSchedulingEngine()
    private let reconciler = AlarmReconciler()

    init(
        policy: any AlarmPolicyEngine,
        alarms: any AlarmRepository,
        audit: any AuditRepository,
        outbox: any OutboxRepository,
        alarmManager: any AlarmManagerAdapter,
        clock: any WallClock,
        ids: any IdentifierGenerator,
        deviceTimeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.policy = policy
        self.alarms = alarms
        self.audit = audit
        self.outbox = outbox
        self.alarmManager = alarmManager
        self.clock = clock
        self.ids = ids
        self.deviceTimeZone = deviceTimeZone
    }

    /// Who/what/where of a command in flight — travels together through the flow.
    private struct CommandContext: Sendable {
        let command: AlarmCommand
        let actor: AuditActor
        let source: CommandSource
    }

    /// Authorize, then apply. Every command is authorized (#3) and audited (#46).
    /// `userConfirmed` is passed to the policy engine, which requires it to cancel /
    /// delay / weaken a critical or imminent alarm (#6).
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
            // The policy withheld a destructive change pending confirmation (#6). Audit the
            // gate (no mutation) and surface it distinctly so the UI can prompt and re-submit.
            await appendAudit(context, old: nil, new: nil, outcome: .rejected, reason: reason)
            return .needsConfirmation(reason: reason)
        }
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
        case .snooze, .cancelOccurrence, .rescheduleOccurrence:
            // Occurrence-level commands (WG-027 follow-on). Not applying them would
            // silently discard user intent, so surface `.unsupported`, never `.noOp`.
            let reason = "This action isn't available yet; the alarm is unchanged."
            await appendAudit(context, old: nil, new: nil, outcome: .noOp, reason: reason)
            return .unsupported(reason: reason)
        default:
            // markChallengePassed (WG-073 stop) / reconcile / recover (WG-029):
            // authorized and audited here; not applying them fails safe (the alarm
            // keeps its scheduled state).
            await appendAudit(
                context, old: nil, new: nil, outcome: .noOp,
                reason: "Accepted; applied by another subsystem.")
            return .noOp
        }
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

    /// Delete the alarm: drop local state first (the source of truth, #10), audit it, then make
    /// a best-effort system cancel through the outbox. Once the local delete succeeds the delete
    /// is **done** from the user's view, so the system cancel's result is not propagated as the
    /// delete's outcome — a failed/uncertain cancel leaves at most an "extra" system alarm, which
    /// is the safe direction for a wake app (a spurious ring, never a missed alarm) and which the
    /// WG-029 reconciliation pass reaps once its launch/foreground trigger is composed. Reversing
    /// the order (cancel-then-delete) is rejected: a cancel that succeeds before a failed local
    /// delete would silently stop a still-listed alarm from ringing — the dangerous direction.
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
        // Enqueue + attempt the system cancel, but do not let its outcome downgrade the delete:
        // the local record (source of truth) is already gone, so the alarm is deleted regardless.
        let key = outboxKey(id, alarm.revision, "cancel", nil)
        _ = await runExternal(key, context.command) {
            try await self.alarmManager.cancel(alarmID: id)
        }
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
            let request = AlarmScheduleRequest(
                alarmID: alarm.id, fireTime: occurrence, title: alarm.label,
                isCritical: alarm.criticality == .critical)
            let key = outboxKey(alarm.id, alarm.revision, "schedule", occurrence)
            return await runExternal(key, context.command) {
                try await self.alarmManager.schedule(request)
            }
        }
        let key = outboxKey(alarm.id, alarm.revision, "cancel", nil)
        return await runExternal(key, context.command) {
            try await self.alarmManager.cancel(alarmID: alarm.id)
        }
    }

    /// The outbox brackets the external call. `enqueue` dedups on the key, so re-read
    /// the stored entry and mark *its* id — not the freshly-minted one, which may not
    /// have been inserted. An already-`applied` entry means the op is done (idempotent
    /// re-process); an exhausted retry budget (or a concurrent owner) means we do NOT
    /// call the adapter again. Best-effort post-call marks — reconciliation recovers a
    /// stranded entry (#10; WG-029).
    private func runExternal(
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
        } catch AlarmManagerError.uncertain {
            if let entryID { try? await outbox.markUncertain(entryID) }
            return .uncertain
        } catch is CancellationError {
            // A cancelled call may already have applied — reconcile, never assume it
            // did not happen (#10).
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

    /// A stable idempotency key per logical operation: an alarm's revision bumps on
    /// every mutation, so a re-issue of the same command dedups but a new mutation does
    /// not (WG-016 at-most-once).
    private func outboxKey(_ id: AlarmID, _ revision: Int, _ kind: String, _ fireTime: Date?)
        -> String
    {
        var key = "\(id.rawValue.uuidString):r\(revision):\(kind)"
        if let fireTime { key += ":\(Int(fireTime.timeIntervalSince1970))" }
        return key
    }

    private func appendAudit(
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

/// Launch/foreground reconciliation (WG-029). Kept in an extension so the core command
/// path and the reconciliation path each stay within the type-body budget; both are
/// actor-isolated and share the same single adapter-invoking boundary (#2).
extension AlarmCommandProcessor {
    /// Make the system authority match the persisted desired state. Reads ground truth
    /// and the desired alarms, plans the safe repairs (missing / extra / divergent), and
    /// applies each through the adapter as a `.systemReconciliation` action, auditing
    /// every repair (#46, #50). The plan is idempotent, so re-running when nothing
    /// diverged is a no-op.
    ///
    /// **Fails safe (#10):** if ground truth *or* the desired state cannot be read it
    /// repairs nothing and returns `skipped` — it never repairs against an unknown system
    /// (which could strand a divergence), and never treats a *failed* desired read as "no
    /// alarms" (which would cancel every system alarm). A repair that hard-fails is
    /// audited and counted; a repair whose outcome is *uncertain* (interrupted /
    /// cancelled) is counted separately and re-checked on the next pass, never dropped.
    func reconcile() async -> ReconciliationSummary {
        guard let system = try? await alarmManager.scheduledAlarms() else {
            return ReconciliationSummary(skipped: true)
        }
        guard let desired = try? await alarms.allAlarms() else {
            return ReconciliationSummary(skipped: true)
        }
        let repairs = reconciler.plan(
            desired: desired, system: system, now: clock.now, deviceTimeZone: deviceTimeZone())
        var summary = ReconciliationSummary()
        for repair in repairs {
            await apply(repair, into: &summary)
        }
        return summary
    }

    /// Apply one repair and fold its outcome into `summary`. An *uncertain* outcome (the
    /// adapter may or may not have applied it) is counted apart from a hard failure: the
    /// local alarm is preserved and the next pass re-checks ground truth and retries (#10).
    private func apply(
        _ repair: ReconciliationRepair, into summary: inout ReconciliationSummary
    ) async {
        let outcome: RepairOutcome
        let scheduled: Bool
        switch repair {
        case .schedule(let request):
            outcome = await applyReconcileSchedule(request)
            scheduled = true
        case .cancel(let id):
            outcome = await applyReconcileCancel(id)
            scheduled = false
        }
        switch outcome {
        case .applied:
            if scheduled { summary.scheduled += 1 } else { summary.cancelled += 1 }
        case .uncertain: summary.uncertain += 1
        case .failed: summary.failed += 1
        }
    }

    private func applyReconcileSchedule(_ request: AlarmScheduleRequest) async -> RepairOutcome {
        let context = CommandContext(
            command: .reconcile(request.alarmID), actor: .systemReconciliation,
            source: .reconciliation)
        do {
            try await alarmManager.schedule(request)
            await appendAudit(
                context, old: nil, new: nil, outcome: .succeeded,
                reason: "Re-synced this alarm to your saved settings.")
            return .applied
        } catch AlarmManagerError.uncertain {
            return await auditUncertainRepair(context)
        } catch is CancellationError {
            return await auditUncertainRepair(context)
        } catch {
            await appendAudit(
                context, old: nil, new: nil, outcome: .failed, reason: Self.reason(for: error))
            return .failed
        }
    }

    private func applyReconcileCancel(_ id: AlarmID) async -> RepairOutcome {
        let context = CommandContext(
            command: .reconcile(id), actor: .systemReconciliation, source: .reconciliation)
        do {
            try await alarmManager.cancel(alarmID: id)
            await appendAudit(
                context, old: nil, new: nil, outcome: .succeeded,
                reason: "Removed a system alarm that no longer matched your settings.")
            return .applied
        } catch AlarmManagerError.uncertain {
            return await auditUncertainRepair(context)
        } catch is CancellationError {
            return await auditUncertainRepair(context)
        } catch {
            await appendAudit(
                context, old: nil, new: nil, outcome: .failed, reason: Self.reason(for: error))
            return .failed
        }
    }

    /// Record a repair whose external outcome is unknown (interrupted / cancelled).
    /// Audited as `.failed` — the safe "treat as not-yet-applied" posture (#10) — with an
    /// honest reason; the next reconciliation pass re-checks ground truth and retries. (A
    /// dedicated `.uncertain` *audit* outcome is a future domain addition — WG-048.)
    private func auditUncertainRepair(_ context: CommandContext) async -> RepairOutcome {
        await appendAudit(
            context, old: nil, new: nil, outcome: .failed,
            reason: "The alarm sync outcome was unknown; it will be re-checked on the next sync.")
        return .uncertain
    }

    /// The outcome of applying one reconciliation repair against the system authority.
    private enum RepairOutcome: Sendable {
        case applied
        /// The adapter call was interrupted / cancelled and may or may not have applied —
        /// the next pass re-checks ground truth (#10), so it is never a hard failure.
        case uncertain
        case failed
    }
}
