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

    /// Delete audit rows by event id — used ONLY by the bounded retention job and the full reset, never by
    /// domain code (the `AuditRepository` port stays append-only, #48). Empty input is a no-op.
    func deleteAuditRecords(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let context = container.newBackgroundContext()
        try await context.perform {
            let fetch = NSFetchRequest<any NSFetchRequestResult>(entityName: "AuditRecord")
            fetch.predicate = NSPredicate(format: "id IN %@", ids)
            try context.execute(NSBatchDeleteRequest(fetchRequest: fetch))
        }
    }
}
