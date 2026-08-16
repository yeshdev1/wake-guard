import CoreData
import Foundation

/// The Core Data-backed `AlarmActivityStore` (WG-299): one `AlarmActivityRecord` row per rung alarm's
/// challenge, keyed `"uuid|epochSeconds"` with a uniqueness constraint so a duplicate record collapses
/// (idempotent). An `actor` owning per-operation background contexts, mirroring the satisfied-wake /
/// feedback store patterns. Stores only interaction facts + the cached plain-English summary — no label,
/// schedule, health, or location value (#41) — on-device only. Best-effort + fail-closed: a write fault
/// drops the one entry; a read fault yields an empty history.
actor CoreDataAlarmActivityStore: AlarmActivityStore {
    private let controller: PersistenceController

    init(_ controller: PersistenceController) {
        self.controller = controller
    }

    private func makeContext() -> NSManagedObjectContext {
        let context = controller.container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.error
        return context
    }

    nonisolated private static func key(_ alarmID: AlarmID, _ occurredAt: Date) -> String {
        "\(alarmID.rawValue.uuidString)|\(Int64(occurredAt.timeIntervalSince1970))"
    }

    func record(_ entry: AlarmActivityEntry) async {
        let activity = entry.activity
        let key = Self.key(activity.alarmID, activity.occurredAt)
        let context = makeContext()
        try? await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "AlarmActivityRecord")
            request.predicate = NSPredicate(format: "activityKey == %@", key)
            request.fetchLimit = 1
            guard try context.fetch(request).first == nil,
                let entity = NSEntityDescription.entity(
                    forEntityName: "AlarmActivityRecord", in: context)
            else { return }
            let record = NSManagedObject(entity: entity, insertInto: context)
            record.setValue(key, forKey: "activityKey")
            record.setValue(activity.occurredAt, forKey: "occurredAt")
            record.setValue(activity.outcome.rawValue, forKey: "outcome")
            record.setValue(activity.walkRequired, forKey: "walkRequired")
            record.setValue(Int64(activity.stepsWalked), forKey: "stepsWalked")
            record.setValue(Int64(activity.requiredSteps), forKey: "requiredSteps")
            record.setValue(Int64(activity.durationSeconds), forKey: "durationSeconds")
            record.setValue(entry.summary, forKey: "summary")
            do {
                try context.save()
            } catch {
                context.rollback()  // a concurrent record won the race — already stored.
            }
        }
    }

    func recentActivities(limit: Int) async -> [AlarmActivityEntry] {
        guard limit > 0 else { return [] }
        let context = makeContext()
        let entries = try? await context.perform { () -> [AlarmActivityEntry] in
            let request = NSFetchRequest<NSManagedObject>(entityName: "AlarmActivityRecord")
            request.sortDescriptors = [NSSortDescriptor(key: "occurredAt", ascending: false)]
            request.fetchLimit = limit
            return try context.fetch(request).compactMap(Self.entry(from:))
        }
        return entries ?? []
    }

    func pruneActivities(olderThan cutoff: Date) async {
        let context = makeContext()
        await context.perform {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "AlarmActivityRecord")
            request.predicate = NSPredicate(format: "occurredAt < %@", cutoff as NSDate)
            let delete = NSBatchDeleteRequest(fetchRequest: request)
            _ = try? context.execute(delete)
        }
    }

    /// Rebuild a domain entry from a row — fail-closed: a row missing the alarm id or an unreadable field
    /// is skipped rather than surfaced as a partial/garbage entry.
    nonisolated private static func entry(from record: NSManagedObject) -> AlarmActivityEntry? {
        guard let key = record.value(forKey: "activityKey") as? String,
            let uuidString = key.split(separator: "|").first.map(String.init),
            let uuid = UUID(uuidString: uuidString),
            let occurredAt = record.value(forKey: "occurredAt") as? Date,
            let outcome = record.value(forKey: "outcome") as? String,
            let summary = record.value(forKey: "summary") as? String
        else { return nil }
        let activity = AlarmActivity(
            alarmID: AlarmID(uuid), occurredAt: occurredAt,
            outcome: AlarmActivityOutcome(fromStored: outcome),
            walkRequired: (record.value(forKey: "walkRequired") as? Bool) ?? true,
            stepsWalked: Int((record.value(forKey: "stepsWalked") as? Int64) ?? 0),
            requiredSteps: Int((record.value(forKey: "requiredSteps") as? Int64) ?? 0),
            durationSeconds: Int((record.value(forKey: "durationSeconds") as? Int64) ?? 0))
        return AlarmActivityEntry(activity: activity, summary: summary)
    }
}
