import CoreData
import Foundation

/// Typed errors from the audit repository.
enum AuditRepositoryError: Error, Equatable {
    /// The audit entity is missing from the model (should be unreachable).
    case storageUnavailable
}

/// A Core Data-backed, **append-only** `AuditRepository` (WG-015). One row per
/// event id (`AuditRecord`: id, denormalized alarmID, timestamp, JSON payload).
///
/// Append-only is enforced by the *port* (WG-012 exposes no update or delete) and
/// by this type only ever inserting: `append` is idempotent on the event id — a
/// repeated id is a no-op, never an overwrite — so a recorded event cannot be
/// changed through the `AuditRepository` API (SAFETY_INVARIANTS #48). This is not a
/// store-level or tamper-evident guarantee: any code in the single app module can
/// open the container directly; hash-chained tamper-evidence is a future ADR.
///
/// The payload is the full `AuditEvent`. State deltas are stored as hashes
/// (`oldStateHash`/`newStateHash`), and #41's *enumerated* sensitive categories —
/// health samples, precise location, calendar titles, journal text, LLM prompts —
/// are excluded by construction: no such field exists anywhere in the
/// `AuditEvent`/`AlarmCommand`/`Alarm` graph. Note that `.create`/`.update` embed
/// the full `Alarm`, including its free-text `label`, which is therefore stored
/// verbatim; redacting `label` from the trail is a deferred decision (DECISIONS
/// WG-015, tracking #42/#43).
actor CoreDataAuditRepository: AuditRepository {
    private let controller: PersistenceController

    init(_ controller: PersistenceController) {
        self.controller = controller
    }

    private func makeContext() -> NSManagedObjectContext {
        let context = controller.container.newBackgroundContext()
        // Reject on conflict (mirrors the alarm repository): a concurrent insert of
        // the same event id surfaces as a constraint conflict, which `append`
        // absorbs as an idempotent no-op rather than duplicating the row.
        context.mergePolicy = NSMergePolicy.error
        return context
    }

    nonisolated private func request(id: AuditEventID) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "AuditRecord")
        request.predicate = NSPredicate(format: "id == %@", id.rawValue.uuidString)
        request.fetchLimit = 1
        return request
    }

    /// A fetch ordered by `(timestamp, id)` — chronological, with a deterministic
    /// tiebreak so equal-instant events return in a stable order. A `nil` alarm
    /// selects every event (diagnostics); otherwise it filters to one alarm's
    /// history (#49).
    nonisolated private func query(forAlarm alarmID: AlarmID?) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "AuditRecord")
        if let alarmID {
            request.predicate = NSPredicate(
                format: "alarmID == %@", alarmID.rawValue.uuidString)
        }
        request.sortDescriptors = [
            NSSortDescriptor(key: "timestamp", ascending: true),
            NSSortDescriptor(key: "id", ascending: true),
        ]
        return request
    }

    func append(_ event: AuditEvent) async throws {
        let data = try JSONEncoder().encode(event)
        let context = makeContext()
        try await context.perform {
            // Idempotent and append-only: if this id already exists, do nothing —
            // never fetch-then-*update*, so a recorded event is immutable (#48). This
            // assumes the caller precondition that an `AuditEventID` identifies
            // exactly one event's content; a reused id carrying different content
            // would be silently dropped here, not detected (ids come from the
            // injected generator, so reuse is a defect, not an expected input).
            if try context.fetch(self.request(id: event.id)).first != nil {
                return
            }
            guard
                let entity = NSEntityDescription.entity(
                    forEntityName: "AuditRecord", in: context)
            else {
                throw AuditRepositoryError.storageUnavailable
            }
            let record = NSManagedObject(entity: entity, insertInto: context)
            record.setValue(event.id.rawValue.uuidString, forKey: "id")
            record.setValue(event.alarmID.rawValue.uuidString, forKey: "alarmID")
            record.setValue(event.timestamp, forKey: "timestamp")
            record.setValue(data, forKey: "payload")
            do {
                try context.save()
            } catch let error as NSError where Self.isConflict(error) {
                // A concurrent append of the same id won the race; the event is
                // already recorded, so this append is satisfied (idempotent). Discard
                // our losing insert rather than duplicating the row.
                context.rollback()
            }
        }
    }

    func events(forAlarm id: AlarmID) async throws -> [AuditEvent] {
        try await fetchEvents(forAlarm: id)
    }

    func allEvents() async throws -> [AuditEvent] {
        try await fetchEvents(forAlarm: nil)
    }

    private func fetchEvents(forAlarm alarmID: AlarmID?) async throws -> [AuditEvent] {
        let context = makeContext()
        return try await context.perform {
            // Build the request inside `perform`: `NSFetchRequest` is not `Sendable`,
            // so it must not cross the context boundary (mirrors the alarm repo).
            let request = self.query(forAlarm: alarmID)
            return try context.fetch(request).compactMap { record -> AuditEvent? in
                guard let data = record.value(forKey: "payload") as? Data else {
                    return nil
                }
                // Skip (don't rethrow) an undecodable row — e.g. a payload written by
                // a future schema, or bit-rot. One poison row must not blind the whole
                // history/diagnostic query (#49); the row stays in the store, so
                // append-only is preserved — it is only dropped from this view.
                // Surfacing a count of skipped rows is a follow-up (needs diagnostics
                // infra; never log the raw payload, #41). Encoding on `append` stays
                // strict, so a corrupt *write* still fails loudly.
                return try? JSONDecoder().decode(AuditEvent.self, from: data)
            }
        }
    }

    /// Whether a Core Data save error is a uniqueness conflict from a concurrent
    /// insert of the same event id (`NSManagedObjectConstraintMergeError`), or the
    /// generic merge error the `error` policy raises.
    private static func isConflict(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain
            && (error.code == NSManagedObjectMergeError
                || error.code == NSManagedObjectConstraintMergeError)
    }
}
