import Foundation

/// The production retention/reap job (WG-250/182) — a launch/foreground caller that prunes old bookkeeping
/// **in the store** (batch deletes, no full-table load), so it stays cheap as the log grows:
///
/// - **Audit** rows past their retention window are batch-deleted via
///   `PersistenceController.pruneAuditRecords`, implementing the same policy as the pure `RetentionCleanup`
///   spec — the general window, with a longer floor for audit about a currently-critical alarm (#48), so a
///   safety-relevant change is never purged early. Deleted on the concrete stack only, so the append-only
///   `AuditRepository` port is untouched.
/// - **Outbox** rows older than a conservative window are reaped, bounding otherwise-unbounded growth
///   (ground-truth reconciliation — not the outbox — drives recovery; keys embed the alarm revision + fire
///   time, so dedup isn't weakened).
///
/// Opportunistic + best-effort (#9): never required, never throws to the caller — a failure just leaves the
/// rows for the next run.
struct RetentionCleanupJob: Sendable {
    let persistence: PersistenceController
    let alarms: any AlarmRepository
    let clock: any WallClock
    var policy: RetentionPolicy = .default

    /// Operational outbox rows are reaped after this long — far past any operation + retry window, so no
    /// in-flight op or crash recovery is lost (ground-truth reconciliation drives recovery, not the outbox).
    static let outboxRetention: TimeInterval = 30 * 86_400

    /// Satisfied-wake rows (WG-290) are reaped after this long — nothing reads one past the ring window,
    /// so two days is generous slack.
    static let satisfiedWakeRetention: TimeInterval = 2 * 86_400

    func run() async {
        let now = clock.now
        let softCutoff = now.addingTimeInterval(-policy.audit)
        // The hard cutoff is the longer of the general window and the critical floor, matching the pure
        // `RetentionCleanup.expired` policy — critical-alarm audit is kept at least the floor.
        let hardFloor = now.addingTimeInterval(
            -max(policy.audit, RetentionPolicy.criticalAuditMinimum))
        let criticalIDs = await criticalAlarmIDStrings()
        try? await persistence.pruneAuditRecords(
            softCutoff: softCutoff, hardFloor: hardFloor, criticalAlarmIDs: criticalIDs)
        try? await persistence.pruneOutboxRecords(
            before: now.addingTimeInterval(-Self.outboxRetention))
        try? await persistence.pruneSatisfiedWakes(
            before: now.addingTimeInterval(-Self.satisfiedWakeRetention))
    }

    private func criticalAlarmIDStrings() async -> [String] {
        guard let all = try? await alarms.allAlarms() else { return [] }
        return all.filter { $0.criticality == .critical }.map { $0.id.rawValue.uuidString }
    }
}
