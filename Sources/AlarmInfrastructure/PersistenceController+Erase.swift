import CoreData
import Foundation

/// Bulk-erase primitives for the privacy controls (WG-250): a full-reset "clear every entity" and a
/// bounded audit-row delete for the retention job. Both use `NSBatchDeleteRequest` on a background context,
/// so the store is cleared without loading the object graph. The app's repositories use a fresh context per
/// operation, so a read after an erase sees the deletion (the batch delete goes straight to the store).
extension PersistenceController {

    /// Erase every row of every entity — the full reset (WG-250). Callers holding a context must refetch.
    func eraseAllEntities() async throws {
        let context = container.newBackgroundContext()
        let names = container.managedObjectModel.entities.compactMap(\.name)
        try await context.perform {
            for name in names {
                let fetch = NSFetchRequest<any NSFetchRequestResult>(entityName: name)
                try context.execute(NSBatchDeleteRequest(fetchRequest: fetch))
            }
        }
    }

    /// Prune audit rows past their retention window **in the store** (WG-182 scaling) — no full-table load.
    /// Two batch deletes implement the policy exactly (matching `RetentionCleanup.expired`, the pure spec):
    /// everything past the critical floor (`hardFloor`), plus non-critical rows past the general window
    /// (`softCutoff`). Audit about a currently-critical alarm is spared until the floor (#48). Used only by
    /// the retention job on the concrete stack, so the append-only `AuditRepository` port is untouched.
    func pruneAuditRecords(softCutoff: Date, hardFloor: Date, criticalAlarmIDs: [String])
        async throws
    {
        let context = container.newBackgroundContext()
        try await context.perform {
            // Everything older than the critical floor expires (critical + non-critical).
            let hard = NSFetchRequest<any NSFetchRequestResult>(entityName: "AuditRecord")
            hard.predicate = NSPredicate(format: "timestamp < %@", hardFloor as NSDate)
            try context.execute(NSBatchDeleteRequest(fetchRequest: hard))
            // Non-critical rows older than the general window expire; currently-critical alarms are spared.
            let soft = NSFetchRequest<any NSFetchRequestResult>(entityName: "AuditRecord")
            soft.predicate = NSPredicate(
                format: "timestamp < %@ AND NOT (alarmID IN %@)", softCutoff as NSDate,
                criticalAlarmIDs)
            try context.execute(NSBatchDeleteRequest(fetchRequest: soft))
        }
    }

    /// Reap operational outbox rows older than `cutoff` (WG-250 scaling) — the outbox is at-most-once dedup
    /// + short-window crash recovery, and ground-truth reconciliation (not the outbox) drives recovery, so
    /// an entry older than the cutoff can be reaped without losing recovery. Keys embed the alarm revision +
    /// fire time, so dedup isn't weakened. Bounds otherwise-unbounded growth. Store-side, no load.
    func pruneOutboxRecords(before cutoff: Date) async throws {
        let context = container.newBackgroundContext()
        try await context.perform {
            let fetch = NSFetchRequest<any NSFetchRequestResult>(entityName: "OutboxRecord")
            fetch.predicate = NSPredicate(format: "createdAt < %@", cutoff as NSDate)
            try context.execute(NSBatchDeleteRequest(fetchRequest: fetch))
        }
    }

    /// Reap satisfied-wake rows older than `cutoff` (WG-290) — nothing reads a row older than the ring
    /// window, so a short cutoff keeps the table trivially bounded. Store-side, no load.
    func pruneSatisfiedWakes(before cutoff: Date) async throws {
        let context = container.newBackgroundContext()
        try await context.perform {
            let fetch = NSFetchRequest<any NSFetchRequestResult>(entityName: "SatisfiedWakeRecord")
            fetch.predicate = NSPredicate(format: "satisfiedAt < %@", cutoff as NSDate)
            try context.execute(NSBatchDeleteRequest(fetchRequest: fetch))
        }
    }

    /// Reap alarm-activity rows older than `cutoff` (WG-299) — the retention window (#43) that keeps the
    /// on-device wake history bounded. Store-side batch delete, no load.
    func pruneAlarmActivities(before cutoff: Date) async throws {
        let context = container.newBackgroundContext()
        try await context.perform {
            let fetch = NSFetchRequest<any NSFetchRequestResult>(entityName: "AlarmActivityRecord")
            fetch.predicate = NSPredicate(format: "occurredAt < %@", cutoff as NSDate)
            try context.execute(NSBatchDeleteRequest(fetchRequest: fetch))
        }
    }

    /// The audit events as their **already-stored JSON payloads**, newest first — for the data export
    /// (WG-183) without decoding each into an `AuditEvent` and re-encoding it (the export just needs the
    /// JSON). Faults in batches (`fetchBatchSize`) so peak memory stays bounded even for a large log.
    func auditPayloadsJSON() async throws -> [String] {
        let context = container.newBackgroundContext()
        return try await context.perform {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "AuditRecord")
            fetch.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            fetch.fetchBatchSize = 200
            return try context.fetch(fetch).compactMap { record in
                (record.value(forKey: "payload") as? Data).flatMap {
                    String(data: $0, encoding: .utf8)
                }
            }
        }
    }
}
