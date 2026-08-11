import Foundation

/// The production retention job (WG-250/182) — the launch/foreground caller of `RetentionCleanup`. It
/// gathers the audit log's records (the only category with a persistent store today), asks the pure
/// `RetentionCleanup` which are past their window (the 365-day critical-audit floor applies automatically),
/// and deletes exactly those.
///
/// Opportunistic + best-effort (#9): never required, never throws to the caller — a read/delete failure
/// just leaves the rows for the next run. Audit rows are deleted through the concrete store only, so the
/// append-only `AuditRepository` port is untouched (#48); the deletion is bounded by the critical-audit
/// floor, so a safety-relevant change to a critical alarm is never purged early (see the WG-250 ADR).
struct RetentionCleanupJob: Sendable {
    let persistence: PersistenceController
    let audit: any AuditRepository
    let alarms: any AlarmRepository
    let clock: any WallClock
    var policy: RetentionPolicy = .default

    func run() async {
        guard let events = try? await audit.allEvents() else { return }
        let criticalIDs = await criticalAlarmIDs()
        // Pair each audit event with a RetentionRecord (category .audit; critical flag from its alarm).
        let records = events.map { event in
            (
                id: event.id.rawValue.uuidString,
                record: RetentionRecord(
                    category: .audit, createdAt: event.timestamp,
                    isCriticalAudit: criticalIDs.contains(event.command.alarmID))
            )
        }
        let expired = Set(
            RetentionCleanup.expired(records.map(\.record), policy: policy, now: clock.now))
        let expiredIDs = records.filter { expired.contains($0.record) }.map(\.id)
        try? await persistence.deleteAuditRecords(ids: expiredIDs)
    }

    private func criticalAlarmIDs() async -> Set<AlarmID> {
        guard let all = try? await alarms.allAlarms() else { return [] }
        return Set(all.filter { $0.criticality == .critical }.map(\.id))
    }
}
