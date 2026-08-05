import Foundation

/// The result of processing an `AlarmCommand`.
enum CommandOutcome: Sendable, Equatable {
    case applied
    case rejected(reason: String)
    case failed(reason: String)
    /// Local state was applied, but the external (AlarmKit) outcome is unknown — the
    /// outbox entry is left `.uncertain` for reconciliation to resolve (#10).
    case uncertain
    /// A command the processor does not yet apply and whose non-application **fails
    /// safe** (the alarm keeps its current scheduled state) — e.g. reconcile/recover.
    case noOp
    /// A command the processor does not yet apply and whose non-application would
    /// **discard user intent** (snooze / skip / reschedule an occurrence). Returned
    /// (not `.noOp`) so a caller can never mistake a dropped snooze for success and
    /// must tell the user the alarm is unchanged.
    case unsupported(reason: String)
}

/// Applies an authorized `AlarmCommand` transactionally to local state and AlarmKit
/// through the outbox/reconciliation pattern (WG-027; ARCHITECTURE §6). It is the
/// **single command-serialization boundary** and the only invoker of the
/// `AlarmManagerAdapter` (#2). An `actor` for isolation; strict no-interleave
/// serialization under concurrent commands is a follow-up (a dedicated serialization
/// task — the actor releases isolation at each `await`, so overlapping commands can
/// interleave; the alarm repo's optimistic-revision guard still prevents a lost
/// update).
///
/// Per command: authorize (#3) — a rejection mutates nothing; then persist local state
/// first (the source of truth, #10), audit the mutation (#46), and sync to AlarmKit
/// with the outbox bracketing the external call so a crash or uncertain outcome is
/// recoverable (#10). Alarms are scheduled per-occurrence `.fixed` (WG-026); re-arming
/// the next occurrence and recovering a stranded outbox entry are reconciliation's job
/// (WG-029). The audit records the *local* mutation; the external sync outcome lives
/// in the outbox (a full history joins the two — WG-048).
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
        if case .rejected(let reason) = await policy.authorize(
            command, from: source, userConfirmed: userConfirmed)
        {
            await appendAudit(context, old: nil, new: nil, outcome: .rejected, reason: reason)
            return .rejected(reason: reason)
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

    /// A stable, non-reversible state fingerprint (FNV-1a over the encoded alarm) — a
    /// hash, never the raw state, so the audit records that state changed without
    /// storing it (#41; #46 old/new state). Used only for intra-trail change detection
    /// (old vs new of the same era), not as a cross-version-stable digest.
    private static func hash(_ alarm: Alarm) -> String {
        guard let data = try? JSONEncoder().encode(alarm) else { return "unencodable" }
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", value)
    }

    private static func reason(for error: Error) -> String {
        if let error = error as? AlarmManagerError, case .notAuthorized = error {
            return "Not authorized to schedule alarms."
        }
        return "The alarm could not be updated in the system."
    }

    /// Distinguish a concurrent-edit conflict (the caller should reload and retry) from
    /// a genuine storage failure.
    private static func saveFailureReason(for error: Error) -> String {
        if let error = error as? AlarmRepositoryError {
            switch error {
            case .staleRevision, .conflict:
                return "This alarm was changed elsewhere; reload and retry."
            case .storageUnavailable:
                return "The alarm could not be saved."
            }
        }
        return "The alarm could not be saved."
    }
}
