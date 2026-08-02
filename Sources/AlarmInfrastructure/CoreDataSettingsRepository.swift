import CoreData
import Foundation

/// A Core Data-backed `SettingsRepository` (ADR-002). Settings are stored as a
/// single-row JSON blob (`SettingsRecord.payload`); every read/write runs on a
/// private background context via `perform`, so the actor never touches a Core
/// Data context off its confined queue. Sharing the same `SettingsRepository`
/// contract as `InMemorySettingsRepository` is what WG-013 demonstrates.
actor CoreDataSettingsRepository: SettingsRepository {
    private let controller: PersistenceController

    init(_ controller: PersistenceController) {
        self.controller = controller
    }

    /// A background context whose merge policy is last-writer-wins, so a concurrent
    /// save resolves against the `singletonKey` uniqueness constraint into a single
    /// row rather than duplicating (WG-013 B1). (The alarm repository will want the
    /// opposite, reject-on-conflict, policy for optimistic revisions — WG-014.)
    private func makeContext() -> NSManagedObjectContext {
        let context = controller.container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }

    /// Returns the stored settings, or the fail-safe `AppSettings.default` (all
    /// smart/optional features off) when the store is empty.
    func settings() async throws -> AppSettings {
        let context = makeContext()
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "SettingsRecord")
            request.fetchLimit = 1
            guard let record = try context.fetch(request).first,
                let data = record.value(forKey: "payload") as? Data
            else {
                return AppSettings.default
            }
            return try JSONDecoder().decode(AppSettings.self, from: data)
        }
    }

    func save(_ settings: AppSettings) async throws {
        let data = try JSONEncoder().encode(settings)
        let context = makeContext()
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "SettingsRecord")
            request.fetchLimit = 1
            let record: NSManagedObject
            if let existing = try context.fetch(request).first {
                record = existing
            } else {
                guard
                    let entity = NSEntityDescription.entity(
                        forEntityName: "SettingsRecord", in: context)
                else {
                    throw PersistenceError.entityNotFound("SettingsRecord")
                }
                record = NSManagedObject(entity: entity, insertInto: context)
            }
            record.setValue(0, forKey: "singletonKey")
            record.setValue(data, forKey: "payload")
            try context.save()
        }
    }
}
