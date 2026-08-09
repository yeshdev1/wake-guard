import CoreData
import Foundation

/// The persisted pre-alarm prompt ledger (WG-089): an **atomic idempotency claim** per (alarm,
/// occurrence), so a prompt surfaces at most once whether triggered by the background opportunity
/// (WG-088) or the foreground fallback — and the de-dup **survives app relaunch**. An `actor` (owns a
/// Core Data context). Fail-closed: a storage error suppresses the prompt (`false`) rather than risk a
/// duplicate; the alarm is unaffected either way. Prunes claims older than `retention` on each claim
/// so the store stays bounded (a past occurrence's key never matches a future one).
actor CoreDataPreAlarmPromptLedger: PreAlarmPromptLedger {
    /// How long a claim is retained. Comfortably longer than any pre-alarm lead window, so a
    /// same-morning re-evaluation still de-dups, while yesterday's claims are reaped.
    static let retention: TimeInterval = 48 * 3600

    private let controller: PersistenceController

    init(_ controller: PersistenceController) {
        self.controller = controller
    }

    private func makeContext() -> NSManagedObjectContext {
        let context = controller.container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.error
        return context
    }

    nonisolated private func request(key: String) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PreAlarmPromptRecord")
        request.predicate = NSPredicate(format: "idempotencyKey == %@", key)
        request.fetchLimit = 1
        return request
    }

    func claim(_ key: PreAlarmPromptKey, at now: Date) async -> Bool {
        let identifier = key.identifier
        let context = makeContext()
        do {
            return try await context.perform {
                // Idempotent: already claimed → suppress (never surface a duplicate).
                if try context.fetch(self.request(key: identifier)).first != nil { return false }
                let record = NSEntityDescription.insertNewObject(
                    forEntityName: "PreAlarmPromptRecord", into: context)
                record.setValue(identifier, forKey: "idempotencyKey")
                record.setValue(now, forKey: "surfacedAt")
                self.pruneExpired(before: now.addingTimeInterval(-Self.retention), in: context)
                do {
                    try context.save()
                    return true
                } catch let error as NSError where Self.isConflict(error) {
                    // A concurrent claim won the uniqueness race — this caller is the loser, so
                    // suppress the duplicate (the expected, non-error outcome; mirror the outbox).
                    context.rollback()
                    return false
                }
            }
        } catch {
            // A genuine storage fault (not the concurrent-loser conflict above) — fail closed:
            // suppress rather than risk a duplicate. A persistently wedged store thus silently
            // disables pre-alarm prompts, which is safe: the alarm is unaffected (WG-089 ADR).
            return false
        }
    }

    /// A uniqueness-constraint / merge conflict (a concurrent claim won) — distinct from a genuine
    /// storage fault. Mirrors `CoreDataOutboxRepository.isConflict`.
    private static func isConflict(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain
            && (error.code == NSManagedObjectMergeError
                || error.code == NSManagedObjectConstraintMergeError)
    }

    nonisolated private func pruneExpired(before cutoff: Date, in context: NSManagedObjectContext) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PreAlarmPromptRecord")
        request.predicate = NSPredicate(format: "surfacedAt < %@", cutoff as NSDate)
        if let stale = try? context.fetch(request) { stale.forEach(context.delete) }
    }
}
