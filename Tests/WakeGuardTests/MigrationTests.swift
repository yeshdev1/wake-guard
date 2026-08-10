import CoreData
import XCTest

@testable import WakeGuard

/// WG-017: the Core Data schema-migration harness. Verifies a store created at **every** historical
/// schema version migrates forward to the latest model preserving its data (additive
/// inferred-lightweight migration), that the migrated store carries the newest entity, and that an
/// **incompatible** open fails cleanly and leaves the user's data recoverable (#10). Runs in CI over
/// on-disk temp stores (migration is inherently file-based).
final class MigrationTests: XCTestCase {

    // MARK: - Core Data helpers

    private func uniqueStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "wg-migration-\(UUID().uuidString).sqlite")
    }

    private func removeStore(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func loadStore(model: NSManagedObjectModel, at url: URL, migrate: Bool) throws
        -> NSPersistentContainer
    {
        let container = NSPersistentContainer(name: "WakeGuard", managedObjectModel: model)
        let description = try XCTUnwrap(container.persistentStoreDescriptions.first)
        description.url = url
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = migrate
        description.shouldInferMappingModelAutomatically = migrate
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    private func close(_ container: NSPersistentContainer) throws {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores { try coordinator.remove(store) }
    }

    private func insertSettings(_ container: NSPersistentContainer, key: Int16, payload: Data)
        throws
    {
        let context = container.viewContext
        try context.performAndWait {
            let record = NSEntityDescription.insertNewObject(
                forEntityName: "SettingsRecord", into: context)
            record.setValue(key, forKey: "singletonKey")
            record.setValue(payload, forKey: "payload")
            try context.save()
        }
    }

    private func settingsPayload(_ container: NSPersistentContainer, key: Int16) throws -> Data? {
        let context = container.viewContext
        return try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "SettingsRecord")
            request.predicate = NSPredicate(format: "singletonKey == %d", key)
            return try context.fetch(request).first?.value(forKey: "payload") as? Data
        }
    }

    private func insertNewestEntity(_ container: NSPersistentContainer) throws {
        // The v6 `PreAlarmFeedbackRecord` — inserting it proves the migrated store carries the latest
        // schema, not just the old subset.
        let context = container.viewContext
        try context.performAndWait {
            let record = NSEntityDescription.insertNewObject(
                forEntityName: "PreAlarmFeedbackRecord", into: context)
            record.setValue(Int16(1), forKey: "singletonKey")
            record.setValue(Int64(0), forKey: "notAwakeCount")
            record.setValue(Int64(0), forKey: "helpfulCount")
            try context.save()
        }
    }

    // MARK: - Tests

    func testMigratesFromEverySchemaVersionPreservingData() throws {
        let fixture = Data("wg-migration-fixture".utf8)
        // From each historical version to the latest (v1…v5 → v6). `SettingsRecord` exists in every
        // version, so it is the invariant fixture whose survival proves data is preserved.
        for version in 1..<PersistenceController.latestSchemaVersion {
            let url = uniqueStoreURL()
            defer { removeStore(url) }

            let old = try loadStore(
                model: PersistenceController.makeModel(throughVersion: version), at: url,
                migrate: false)
            try insertSettings(old, key: Int16(version), payload: fixture)
            try close(old)

            let migrated = try loadStore(
                model: PersistenceController.makeModel(), at: url, migrate: true)
            defer { try? close(migrated) }
            XCTAssertEqual(
                try settingsPayload(migrated, key: Int16(version)), fixture,
                "settings data survived migration from v\(version) to the latest schema")
            // The migrated store is fully upgraded — the newest entity is usable.
            try insertNewestEntity(migrated)
        }
    }

    func testIncompatibleOpenFailsAndPreservesRecoverableData() throws {
        // A latest-schema store with data.
        let fixture = Data("recoverable".utf8)
        let url = uniqueStoreURL()
        defer { removeStore(url) }
        let full = try loadStore(model: PersistenceController.makeModel(), at: url, migrate: false)
        try insertSettings(full, key: 1, payload: fixture)
        try close(full)

        // Opening it with an OLDER, incompatible model **without** migration must fail — a mismatched
        // schema is rejected, never silently discarded, and the source file is left untouched.
        XCTAssertThrowsError(
            try loadStore(
                model: PersistenceController.makeModel(throughVersion: 1), at: url, migrate: false),
            "an incompatible open without migration must fail, not corrupt the store")

        // The user's data is still recoverable with the correct model (#10).
        let recovered = try loadStore(
            model: PersistenceController.makeModel(), at: url, migrate: true)
        defer { try? close(recovered) }
        XCTAssertEqual(
            try settingsPayload(recovered, key: 1), fixture,
            "data is intact after a failed/incompatible open")
    }
}
