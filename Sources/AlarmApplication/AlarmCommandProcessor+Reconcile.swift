import Foundation

/// Launch/foreground reconciliation (WG-029). In its own file so the core command path stays within
/// budget; both are actor-isolated and share the boundary (#2).
extension AlarmCommandProcessor {
    /// Make the system authority match persisted desired state via `.systemReconciliation` repairs,
    /// auditing each (#46/#50). Idempotent; fails safe — an unreadable read repairs nothing (#10).
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

    /// Apply one repair, folding its outcome into `summary`. Re-validate against *current* desired state
    /// first (WG-244): a stale — or unreadable — repair is deferred, never applied (fail closed, #10).
    private func apply(
        _ repair: ReconciliationRepair, into summary: inout ReconciliationSummary
    ) async {
        let stillValid: Bool
        do { stillValid = try await isStillDesired(repair) } catch {
            summary.stale += 1  // read failed → defer, don't act on unknown state (WG-251)
            return
        }
        guard stillValid else {
            summary.stale += 1
            return
        }
        let outcome: RepairOutcome
        let scheduled: Bool
        switch repair {
        case .schedule(let request):
            outcome = await applyRepair(
                request.alarmID, success: "Re-synced this alarm to your saved settings."
            ) { try await self.alarmManager.schedule(request) }
            scheduled = true
        case .cancel(let id):
            outcome = await applyRepair(
                id, success: "Removed a system alarm that no longer matched your settings."
            ) { try await self.alarmManager.cancel(alarmID: id) }
            scheduled = false
        }
        switch outcome {
        case .applied:
            if scheduled { summary.scheduled += 1 } else { summary.cancelled += 1 }
        case .uncertain: summary.uncertain += 1
        case .failed: summary.failed += 1
        }
    }

    /// The lost-update re-validation (WG-244), chain-aware (WG-291): a main-occurrence schedule must
    /// still equal the alarm's current desired request; a **chain member** re-validates against its
    /// *parent's* recomputed chain (the member id is derived, never stored); a cancel is valid only while
    /// nothing desires that id. **Throws** on a read failure so the caller defers (WG-251).
    private func isStillDesired(_ repair: ReconciliationRepair) async throws -> Bool {
        switch repair {
        case .schedule(let request):
            if let parentID = request.parentAlarmID {
                guard let parent = try await alarms.alarm(id: parentID), parent.isEnabled,
                    let occurrence = engine.nextOccurrence(
                        for: parent, after: clock.now, deviceTimeZone: deviceTimeZone())
                else { return false }
                return WakeChain.requests(for: parent, occurrence: occurrence).contains(request)
            }
            return try await currentDesiredSchedule(for: request.alarmID) == request
        case .cancel(let id):
            return try await currentDesiredSchedule(for: id) == nil
        }
    }

    /// The *current* desired schedule for one alarm (the lost-update guard for #10, WG-244). **Throws** on
    /// a read failure so the caller defers rather than acting on unknown state (WG-251).
    private func currentDesiredSchedule(for id: AlarmID) async throws -> AlarmScheduleRequest? {
        guard let alarm = try await alarms.alarm(id: id), alarm.isEnabled,
            let occurrence = engine.nextOccurrence(
                for: alarm, after: clock.now, deviceTimeZone: deviceTimeZone())
        else { return nil }
        return AlarmScheduleRequest(alarm: alarm, fireTime: occurrence)
    }

    /// Apply one repair via `body`, auditing as `.systemReconciliation` (#46/#50). Uncertain/cancelled
    /// → `.uncertain` (re-checked next pass, #10); a thrown error → `.failed`. The local alarm survives.
    private func applyRepair(
        _ id: AlarmID, success: String, _ body: () async throws -> Void
    ) async -> RepairOutcome {
        let context = CommandContext(
            command: .reconcile(id), actor: .systemReconciliation, source: .reconciliation)
        do {
            try await body()
            await appendAudit(context, old: nil, new: nil, outcome: .succeeded, reason: success)
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

    /// Record a repair whose external outcome is unknown — audited `.failed` (the safe not-yet-applied
    /// posture, #10); the next pass re-checks. (A distinct `.uncertain` audit outcome is WG-048.)
    private func auditUncertainRepair(_ context: CommandContext) async -> RepairOutcome {
        await appendAudit(
            context, old: nil, new: nil, outcome: .failed,
            reason: "The alarm sync outcome was unknown; it will be re-checked on the next sync.")
        return .uncertain
    }

    /// The outcome of applying one reconciliation repair against the system authority.
    private enum RepairOutcome: Sendable {
        case applied
        /// Interrupted / cancelled — may or may not have applied; the next pass re-checks (#10).
        case uncertain
        case failed
    }
}
