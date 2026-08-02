import CoreData
import Foundation

/// Typed errors from the alarm repository.
enum AlarmRepositoryError: Error, Equatable {
    /// A save whose `incoming` revision was not newer than the `stored` one was
    /// rejected — a stale edit must not overwrite a newer one (optimistic
    /// concurrency).
    case staleRevision(stored: Int, incoming: Int)
    /// A concurrent write to the same alarm conflicted at the store.
    case conflict(AlarmID)
    /// The alarm entity is missing from the model (should be unreachable).
    case storageUnavailable
}

/// A Core Data-backed `AlarmRepository` (WG-014). One row per alarm id
/// (`AlarmRecord`: id, revision, JSON payload). Uses an **error** merge policy
/// (reject on conflict) — the opposite of the settings repository — so a
/// concurrent write is surfaced as a typed error, never silently merged, honoring
/// the optimistic-revision contract (WG-012 `AlarmRepository.save`).
actor CoreDataAlarmRepository: AlarmRepository {
    private let controller: PersistenceController

    init(_ controller: PersistenceController) {
        self.controller = controller
    }

    private func makeContext() -> NSManagedObjectContext {
        let context = controller.container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.error
        return context
    }

    nonisolated private func request(id: AlarmID) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "AlarmRecord")
        request.predicate = NSPredicate(format: "id == %@", id.rawValue.uuidString)
        request.fetchLimit = 1
        return request
    }

    func save(_ alarm: Alarm) async throws {
        let data = try JSONEncoder().encode(alarm)
        let context = makeContext()
        try await context.perform {
            if let existing = try context.fetch(self.request(id: alarm.id)).first {
                let storedRevision = existing.value(forKey: "revision") as? Int ?? 0
                guard alarm.revision > storedRevision else {
                    throw AlarmRepositoryError.staleRevision(
                        stored: storedRevision, incoming: alarm.revision)
                }
                existing.setValue(alarm.revision, forKey: "revision")
                existing.setValue(data, forKey: "payload")
            } else {
                // Insert a new alarm. This fetch-then-insert is TOCTOU by nature; a
                // concurrent insert of the same id is caught not by the fetch but by
                // the `AlarmRecord` uniqueness constraint on save (do not remove it).
                guard
                    let entity = NSEntityDescription.entity(
                        forEntityName: "AlarmRecord", in: context)
                else {
                    throw AlarmRepositoryError.storageUnavailable
                }
                let record = NSManagedObject(entity: entity, insertInto: context)
                record.setValue(alarm.id.rawValue.uuidString, forKey: "id")
                record.setValue(alarm.revision, forKey: "revision")
                record.setValue(data, forKey: "payload")
            }
            do {
                try context.save()
            } catch let error as NSError where Self.isConflict(error) {
                throw AlarmRepositoryError.conflict(alarm.id)
            }
        }
    }

    func alarm(id: AlarmID) async throws -> Alarm? {
        let context = makeContext()
        return try await context.perform {
            guard let record = try context.fetch(self.request(id: id)).first,
                let data = record.value(forKey: "payload") as? Data
            else {
                return nil
            }
            return try JSONDecoder().decode(Alarm.self, from: data)
        }
    }

    func allAlarms() async throws -> [Alarm] {
        let context = makeContext()
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "AlarmRecord")
            return try context.fetch(request).compactMap { record in
                guard let data = record.value(forKey: "payload") as? Data else { return nil }
                return try JSONDecoder().decode(Alarm.self, from: data)
            }
        }
    }

    /// Deletes the alarm if present. Not revision-guarded — a stale delete is not
    /// yet rejected (the port takes no expected revision); routing deletes through
    /// the command processor's revision discipline is WG-027 (see DECISIONS). The
    /// save is still wrapped so a store conflict surfaces as a typed error.
    func deleteAlarm(id: AlarmID) async throws {
        let context = makeContext()
        try await context.perform {
            if let record = try context.fetch(self.request(id: id)).first {
                context.delete(record)
                do {
                    try context.save()
                } catch let error as NSError where Self.isConflict(error) {
                    throw AlarmRepositoryError.conflict(id)
                }
            }
        }
    }

    /// Whether a Core Data save error is an optimistic-lock or uniqueness conflict:
    /// `NSManagedObjectMergeError` (a row we edited changed under us) or
    /// `NSManagedObjectConstraintMergeError` (a concurrent insert of the same id).
    private static func isConflict(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain
            && (error.code == NSManagedObjectMergeError
                || error.code == NSManagedObjectConstraintMergeError)
    }
}
