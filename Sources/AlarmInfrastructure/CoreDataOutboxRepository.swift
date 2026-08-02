import CoreData
import Foundation

/// Typed errors from the outbox repository.
enum OutboxRepositoryError: Error, Equatable {
    /// No entry with that id exists (or its payload was undecodable).
    case notFound(OutboxEntryID)
    /// A transition was attempted on a terminal entry, which would resurrect a
    /// completed/failed external operation (an unsafe double-apply).
    case alreadyResolved(OutboxEntryID)
    /// The retry budget (`maxAttempts`) is exhausted; the entry was moved to
    /// `.failed` and must not be attempted again (no unbounded retries).
    case retryLimitExceeded(OutboxEntryID)
    /// A concurrent write to the same entry conflicted at the store.
    case conflict(OutboxEntryID)
    /// The outbox entity is missing from the model (should be unreachable).
    case storageUnavailable
}

/// A Core Data-backed `OutboxRepository` (WG-016) — the durable queue of external
/// (AlarmKit) operations, so a command applied locally is eventually reconciled to
/// the system even across crashes (ARCHITECTURE §5–§6).
///
/// - **Idempotent enqueue:** at most one entry per `idempotencyKey` (fetch-first +
///   a store uniqueness constraint that absorbs the concurrent race), so a *retried
///   enqueue* queues the operation at most once (WG-012). This alone does not stop
///   two independent processors from each driving one entry — a single
///   command-serialization boundary is the caller's contract (WG-027; ARCHITECTURE
///   §6). A reused key is deduped indefinitely, so keys must be unique per logical
///   operation.
/// - **Guarded state machine:** `pending → inProgress → applied/uncertain/failed`.
///   A *terminal* entry is never resurrected (so a completed op is not re-applied
///   externally), and the `mark*` transitions are idempotent on their own state. A
///   concurrent update to the same entry is rejected with `.conflict` (store
///   optimistic lock — never a silent lost update); the driver re-reads and retries.
/// - **Bounded retries:** `markInProgress` counts attempts and, past `maxAttempts`,
///   fails the entry and throws `retryLimitExceeded` — never an unbounded retry.
///   `markInProgress` means "confirmed not-applied, attempt again", so failing an
///   exhausted op is a confirmed give-up and keeping the alarm active is the
///   caller's safe fallback (#40). An `uncertain` (outcome-unknown) entry must be
///   reconciled against AlarmKit *before* any re-drive — never assumed not-done
///   (#10; WG-029) — since a blind re-drive at the cap would wrongly declare it
///   failed.
/// - **Recovery:** `unresolvedEntries()` returns every *non-terminal* entry for
///   launch reconciliation, so no in-flight operation is stranded (#10). A terminal
///   `.failed` op is intentionally *not* re-surfaced here; recovering a
///   crashed-before-fallback failure is WG-029's independent local-vs-AlarmKit
///   divergence scan, not an outbox scan. An undecodable row is skipped by every
///   query (read-resilience, WG-015) and likewise relies on WG-029 to quarantine it
///   (see DECISIONS WG-016).
actor CoreDataOutboxRepository: OutboxRepository {
    /// Bounded retry budget. Chosen small: AlarmKit operations that fail this many
    /// times are a real fault, not transient, and must surface rather than loop.
    static let maxAttempts = 5

    private let controller: PersistenceController

    init(_ controller: PersistenceController) {
        self.controller = controller
    }

    private func makeContext() -> NSManagedObjectContext {
        let context = controller.container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.error
        return context
    }

    nonisolated private func request(id: OutboxEntryID) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "OutboxRecord")
        request.predicate = NSPredicate(format: "id == %@", id.rawValue.uuidString)
        request.fetchLimit = 1
        return request
    }

    nonisolated private func request(idempotencyKey key: String) -> NSFetchRequest<NSManagedObject>
    {
        let request = NSFetchRequest<NSManagedObject>(entityName: "OutboxRecord")
        request.predicate = NSPredicate(format: "idempotencyKey == %@", key)
        request.fetchLimit = 1
        return request
    }

    /// Entries in any of `statuses`, oldest-first with a deterministic id tiebreak.
    nonisolated private func query(statuses: [OutboxStatus]) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "OutboxRecord")
        request.predicate = NSPredicate(format: "status IN %@", statuses.map(\.rawValue))
        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: true),
            NSSortDescriptor(key: "id", ascending: true),
        ]
        return request
    }

    func enqueue(_ entry: OutboxEntry) async throws {
        // A freshly-enqueued operation is always pending and unattempted — normalize
        // so a caller cannot seed the queue in a mid-lifecycle state (defense in
        // depth; the queue invariant then holds by construction).
        var normalized = entry
        normalized.status = .pending
        normalized.attempts = 0
        let data = try JSONEncoder().encode(normalized)
        let context = makeContext()
        try await context.perform {
            // Idempotent: an operation with this key is already queued/handled — do
            // not insert a duplicate (at-most-once), and never *update* it here.
            if try context.fetch(self.request(idempotencyKey: entry.idempotencyKey)).first != nil {
                return
            }
            guard
                let description = NSEntityDescription.entity(
                    forEntityName: "OutboxRecord", in: context)
            else {
                throw OutboxRepositoryError.storageUnavailable
            }
            let record = NSManagedObject(entity: description, insertInto: context)
            record.setValue(entry.id.rawValue.uuidString, forKey: "id")
            record.setValue(entry.idempotencyKey, forKey: "idempotencyKey")
            record.setValue(OutboxStatus.pending.rawValue, forKey: "status")
            record.setValue(entry.createdAt, forKey: "createdAt")
            record.setValue(data, forKey: "payload")
            do {
                try context.save()
            } catch let error as NSError where Self.isConflict(error) {
                // A concurrent enqueue of the same key won the race — idempotent.
                context.rollback()
            }
        }
    }

    func entry(id: OutboxEntryID) async throws -> OutboxEntry? {
        let context = makeContext()
        return try await context.perform {
            guard let record = try context.fetch(self.request(id: id)).first else { return nil }
            return Self.decode(record)
        }
    }

    func entry(idempotencyKey key: String) async throws -> OutboxEntry? {
        let context = makeContext()
        return try await context.perform {
            guard let record = try context.fetch(self.request(idempotencyKey: key)).first
            else { return nil }
            return Self.decode(record)
        }
    }

    func pendingEntries() async throws -> [OutboxEntry] {
        try await entries(statuses: [.pending])
    }

    func unresolvedEntries() async throws -> [OutboxEntry] {
        // Every non-terminal state — what launch reconciliation must recover so a
        // stranded operation is never lost (#10), not just the freshly-pending ones.
        try await entries(statuses: [.pending, .inProgress, .uncertain])
    }

    private func entries(statuses: [OutboxStatus]) async throws -> [OutboxEntry] {
        let context = makeContext()
        return try await context.perform {
            let request = self.query(statuses: statuses)
            // Skip (don't rethrow) an undecodable row so one poison entry cannot blind
            // recovery; the row stays in the store (WG-015 read-resilience decision).
            return try context.fetch(request).compactMap(Self.decode)
        }
    }

    func markInProgress(_ id: OutboxEntryID) async throws {
        try await apply(.inProgress, to: id)
    }

    func markApplied(_ id: OutboxEntryID) async throws {
        try await apply(.applied, to: id)
    }

    func markUncertain(_ id: OutboxEntryID) async throws {
        try await apply(.uncertain, to: id)
    }

    func markFailed(_ id: OutboxEntryID, reason: String) async throws {
        try await apply(.failed(reason: reason), to: id)
    }

    /// A state-machine transition. `Sendable` (not a closure) so it can cross the
    /// `perform` boundary under Swift 6 complete checking.
    private enum Transition: Sendable {
        case inProgress
        case applied
        case uncertain
        case failed(reason: String)
    }

    /// Loads the entry, runs the pure transition (`resolve`), and persists the
    /// result. A no-op transition writes nothing; an exhausted budget is failed then
    /// signaled. Kept to plumbing only — the state rules live in `resolve`.
    private func apply(_ transition: Transition, to id: OutboxEntryID) async throws {
        let context = makeContext()
        try await context.perform {
            guard let record = try context.fetch(self.request(id: id)).first,
                var entry = Self.decode(record)
            else {
                throw OutboxRepositoryError.notFound(id)
            }
            guard case .changed(let exhausted) = try Self.resolve(transition, on: &entry, id: id)
            else {
                return  // idempotent no-op: nothing to write
            }
            record.setValue(entry.status.rawValue, forKey: "status")
            record.setValue(try JSONEncoder().encode(entry), forKey: "payload")
            do {
                try context.save()
            } catch let error as NSError where Self.isConflict(error) {
                throw OutboxRepositoryError.conflict(id)
            }
            if exhausted {
                throw OutboxRepositoryError.retryLimitExceeded(id)
            }
        }
    }

    /// Outcome of a pure transition: whether the entry changed (and, if so, whether
    /// the change was the retry budget being spent).
    private enum TransitionResult { case noChange, changed(exhausted: Bool) }

    /// The pure state machine (no Core Data): mutate `entry` for `transition`, or
    /// throw `alreadyResolved` for an illegal move off a terminal entry.
    nonisolated private static func resolve(
        _ transition: Transition, on entry: inout OutboxEntry, id: OutboxEntryID
    ) throws -> TransitionResult {
        switch transition {
        case .inProgress: try beginAttempt(&entry, id: id)
        case .applied: try setStatus(&entry, to: .applied, reason: nil, id: id)
        case .uncertain: try setStatus(&entry, to: .uncertain, reason: nil, id: id)
        case .failed(let reason): try setStatus(&entry, to: .failed, reason: reason, id: id)
        }
    }

    /// Records an attempt, bounded by `maxAttempts`. Past the budget the entry is
    /// failed (no unbounded retries) and the caller is told via `exhausted`.
    nonisolated private static func beginAttempt(
        _ entry: inout OutboxEntry, id: OutboxEntryID
    ) throws -> TransitionResult {
        guard !entry.status.isTerminal else {
            throw OutboxRepositoryError.alreadyResolved(id)
        }
        guard entry.attempts < maxAttempts else {
            entry.status = .failed
            entry.lastFailureReason = "retry limit exceeded"
            return .changed(exhausted: true)
        }
        entry.status = .inProgress
        entry.attempts += 1
        return .changed(exhausted: false)
    }

    /// Moves to a non-attempt `target`. Re-applying the current state is an
    /// idempotent no-op; any *other* move off a terminal entry is rejected so a
    /// completed/failed op is never resurrected.
    nonisolated private static func setStatus(
        _ entry: inout OutboxEntry, to target: OutboxStatus, reason: String?, id: OutboxEntryID
    ) throws -> TransitionResult {
        if entry.status == target { return .noChange }
        guard !entry.status.isTerminal else {
            throw OutboxRepositoryError.alreadyResolved(id)
        }
        entry.status = target
        if let reason { entry.lastFailureReason = reason }
        return .changed(exhausted: false)
    }

    /// Decodes a record's payload, returning `nil` on a missing or undecodable blob
    /// (callers treat that as absent rather than propagating one corrupt row).
    nonisolated private static func decode(_ record: NSManagedObject) -> OutboxEntry? {
        guard let data = record.value(forKey: "payload") as? Data else { return nil }
        return try? JSONDecoder().decode(OutboxEntry.self, from: data)
    }

    /// Whether a Core Data save error is a uniqueness/merge conflict from a
    /// concurrent write (mirrors the alarm/audit repositories).
    private static func isConflict(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain
            && (error.code == NSManagedObjectMergeError
                || error.code == NSManagedObjectConstraintMergeError)
    }
}
