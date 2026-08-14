import CoreData
import Foundation

/// The Core Data-backed `SatisfiedWakeStore` (WG-290): one `SatisfiedWakeRecord` row per satisfied
/// (alarm, fire-instant) wake, keyed `"uuid|epochSeconds"` with a uniqueness constraint so a duplicate
/// pass collapses (idempotent). An `actor` owning per-operation contexts, mirroring the ledger/feedback
/// store patterns. Carries no alarm authority: it records and answers one boolean — the commitment lock's
/// failsafe — and stores no label, schedule, or sensitive value (#41). Best-effort + fail-closed: a write
/// fault leaves the lock to expire with the bounded window; a read fault answers "not satisfied".
actor CoreDataSatisfiedWakeStore: SatisfiedWakeStore {
    private let controller: PersistenceController
    private let now: @Sendable () -> Date

    init(_ controller: PersistenceController, now: @escaping @Sendable () -> Date = { Date() }) {
        self.controller = controller
        self.now = now
    }

    private func makeContext() -> NSManagedObjectContext {
        let context = controller.container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.error
        return context
    }

    nonisolated private static func key(_ alarmID: AlarmID, _ fireTime: Date) -> String {
        "\(alarmID.rawValue.uuidString)|\(Int64(fireTime.timeIntervalSince1970))"
    }

    nonisolated private static func request(key: String) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SatisfiedWakeRecord")
        request.predicate = NSPredicate(format: "wakeKey == %@", key)
        request.fetchLimit = 1
        return request
    }

    func markSatisfied(alarmID: AlarmID, fireTime: Date) async {
        let key = Self.key(alarmID, fireTime)
        let stamp = now()
        let context = makeContext()
        try? await context.perform {
            // Fetch-first idempotency; a concurrent duplicate collapses under the store's
            // uniqueness constraint + error merge policy (rolled back, already recorded).
            guard try context.fetch(Self.request(key: key)).first == nil,
                let entity = NSEntityDescription.entity(
                    forEntityName: "SatisfiedWakeRecord", in: context)
            else { return }
            let record = NSManagedObject(entity: entity, insertInto: context)
            record.setValue(key, forKey: "wakeKey")
            record.setValue(stamp, forKey: "satisfiedAt")
            do {
                try context.save()
            } catch {
                context.rollback()  // a concurrent pass won the race — already satisfied.
            }
        }
    }

    func isSatisfied(alarmID: AlarmID, fireTime: Date) async -> Bool {
        let key = Self.key(alarmID, fireTime)
        let context = makeContext()
        let found = try? await context.perform {
            try context.fetch(Self.request(key: key)).first != nil
        }
        return found ?? false  // unreadable → "not satisfied": the lock holds (fail-closed).
    }
}
