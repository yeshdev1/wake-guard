import CoreData
import Foundation

enum PersistenceError: Error, Equatable {
    case noStoreDescription
    case entityNotFound(String)
}

/// The Core Data stack (ADR-002: Core Data primary). Owns a programmatic,
/// **versioned** `NSManagedObjectModel` and an `NSPersistentContainer`,
/// configurable in-memory (tests/previews) or on-disk SQLite (production, with
/// file protection + history tracking). The schema grows in WG-014–016
/// (alarm/audit/outbox entities); the migration test harness is WG-017.
///
/// `@unchecked Sendable` is a **narrow, justified** assertion of Apple's
/// documented contract: an `NSPersistentContainer` is safe to share across
/// threads to create per-thread contexts, and the thread-confined
/// `NSManagedObjectContext`s are always used via `perform`. It is *not* an escape
/// hatch hiding repository-logic races (which ADR-002's background-write gate
/// forbids — repositories keep their own mutable state actor-isolated).
final class PersistenceController: @unchecked Sendable {

    /// The current Core Data schema version (grows as entities are added).
    /// v1: SettingsRecord (WG-013). v2: + AlarmRecord (WG-014).
    /// v3: + AuditRecord (WG-015).
    static let schemaVersion = "3"

    let container: NSPersistentContainer

    init(inMemory: Bool) throws {
        container = NSPersistentContainer(
            name: "WakeGuard", managedObjectModel: Self.makeModel())

        guard let description = container.persistentStoreDescriptions.first else {
            throw PersistenceError.noStoreDescription
        }
        if inMemory {
            // Ephemeral SQLite store — persists across contexts yet leaves nothing
            // on disk.
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.setOption(
                FileProtectionType.complete as NSObject,
                forKey: NSPersistentStoreFileProtectionKey)
        }
        // History tracking is enabled for BOTH stores, so in-memory tests exercise
        // the same reconciliation substrate as production (ADR-002; #10).
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        // `loadPersistentStores` completes synchronously for local stores (SQLite /
        // /dev/null), so capturing the error here is safe. This assumption holds
        // only for synchronously-loaded stores — not e.g. CloudKit, which we don't use.
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        // (No `viewContext.automaticallyMergesChangesFromParent`: background contexts
        // are siblings of viewContext, not children, so it would be a no-op. Wiring a
        // viewContext reader to observe background writes via the remote-change
        // notification is deferred to when a reader exists — see DECISIONS.)
    }

    /// The programmatic managed-object model. Uses generic `NSManagedObject` with
    /// KVC access, so no code-generated subclasses are needed.
    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [makeSettingsEntity(), makeAlarmEntity(), makeAuditEntity()]
        model.versionIdentifiers = [schemaVersion]
        return model
    }

    private static func makeSettingsEntity() -> NSEntityDescription {
        let settings = NSEntityDescription()
        settings.name = "SettingsRecord"
        settings.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        settings.properties = [
            attribute("singletonKey", .integer16AttributeType),
            attribute("payload", .binaryDataAttributeType),
        ]
        // Exactly one settings row: concurrent inserts of the same key collapse
        // under the repository's merge policy rather than duplicating (WG-013 B1).
        settings.uniquenessConstraints = [["singletonKey"]]
        return settings
    }

    private static func makeAlarmEntity() -> NSEntityDescription {
        let alarm = NSEntityDescription()
        alarm.name = "AlarmRecord"
        alarm.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        alarm.properties = [
            attribute("id", .stringAttributeType),
            attribute("revision", .integer64AttributeType),
            attribute("payload", .binaryDataAttributeType),
        ]
        // One row per alarm id; a concurrent insert of the same id is rejected by
        // the alarm repository's error merge policy (WG-014 optimistic concurrency).
        alarm.uniquenessConstraints = [["id"]]
        return alarm
    }

    private static func makeAuditEntity() -> NSEntityDescription {
        let audit = NSEntityDescription()
        audit.name = "AuditRecord"
        audit.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        audit.properties = [
            attribute("id", .stringAttributeType),
            // Denormalized target-alarm id, so history-by-alarm queries (#49) filter
            // in the store instead of decoding every payload.
            attribute("alarmID", .stringAttributeType),
            // Chronological key; queries order by (timestamp, id) for a stable,
            // deterministic sequence even when two events share an instant.
            attribute("timestamp", .dateAttributeType),
            // The full `AuditEvent` as JSON. State deltas are hashed, and #41's
            // enumerated sensitive categories (health/location/calendar/journal/LLM)
            // have no field in the domain graph and so never appear. For
            // create/update the embedded `Alarm` — including its free-text `label` —
            // is stored verbatim (DECISIONS WG-015 tracks a redaction follow-up).
            attribute("payload", .binaryDataAttributeType),
        ]
        // One row per event id. Append is insert-only and idempotent: a repeated id
        // is ignored, never used to overwrite the prior record (#48 append-only).
        audit.uniquenessConstraints = [["id"]]
        return audit
    }

    private static func attribute(
        _ name: String, _ type: NSAttributeType
    ) -> NSAttributeDescription {
        let description = NSAttributeDescription()
        description.name = name
        description.attributeType = type
        description.isOptional = false
        return description
    }
}
