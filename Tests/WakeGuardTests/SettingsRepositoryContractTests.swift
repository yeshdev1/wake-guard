import CoreData
import XCTest

@testable import WakeGuard

/// WG-013: the in-memory and Core Data repositories share one contract, the
/// schema is versioned, and Core Data actually persists across repository
/// instances over the same store.
final class SettingsRepositoryContractTests: XCTestCase {

    /// The behavioral contract every `SettingsRepository` must satisfy.
    private func assertContract(_ repo: some SettingsRepository) async throws {
        let initial = try await repo.settings()
        XCTAssertEqual(initial, .default, "an unset repository returns .default")

        var updated = AppSettings.default
        updated.preAlarmPromptEnabled = true
        updated.analyticsEnabled = true
        try await repo.save(updated)
        let loaded = try await repo.settings()
        XCTAssertEqual(loaded, updated, "saved settings round-trip")

        var reverted = updated
        reverted.preAlarmPromptEnabled = false
        try await repo.save(reverted)
        let reloaded = try await repo.settings()
        XCTAssertEqual(reloaded, reverted, "a second save overwrites")
    }

    func testInMemorySettingsRepositorySatisfiesContract() async throws {
        try await assertContract(InMemorySettingsRepository())
    }

    func testCoreDataSettingsRepositorySatisfiesContract() async throws {
        let controller = try PersistenceController(inMemory: true)
        try await assertContract(CoreDataSettingsRepository(controller))
    }

    func testOnboardingFlagDefaultsFalseAndBackCompatDecodesFalse() throws {
        XCTAssertFalse(
            AppSettings.default.hasCompletedOnboarding, "a fresh install shows onboarding")
        // A blob encoded before the flag existed must decode to false, not throw (WG-200 back-compat).
        let legacy = Data(
            """
            {"preAlarmPromptEnabled":false,"automaticProposalPreparationEnabled":false,\
            "cloudAIEnabled":false,"locationContextEnabled":false,"readinessScoreEnabled":false,\
            "experimentalAntiCheatEnabled":false,"analyticsEnabled":false,"smartFeaturesKillSwitch":false}
            """.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertFalse(decoded.hasCompletedOnboarding)
    }

    func testOnboardingFlagPersists() async throws {
        let repo = InMemorySettingsRepository()
        var settings = AppSettings.default
        settings.hasCompletedOnboarding = true
        try await repo.save(settings)
        let loaded = try await repo.settings()
        XCTAssertTrue(loaded.hasCompletedOnboarding, "the onboarding flag persists across loads")
    }

    func testSchemaIsVersioned() throws {
        XCTAssertFalse(PersistenceController.schemaVersion.isEmpty)
        let controller = try PersistenceController(inMemory: true)
        let identifiers = controller.container.managedObjectModel.versionIdentifiers
        XCTAssertTrue(identifiers.contains(PersistenceController.schemaVersion))
    }

    func testCoreDataPersistsAcrossRepositoryInstances() async throws {
        // Two repositories over the SAME container see each other's writes —
        // proving the Core Data store, not per-instance memory, holds the data.
        let controller = try PersistenceController(inMemory: true)
        let writer = CoreDataSettingsRepository(controller)
        var settings = AppSettings.default
        settings.locationContextEnabled = true
        try await writer.save(settings)

        let reader = CoreDataSettingsRepository(controller)
        let loaded = try await reader.settings()
        XCTAssertEqual(loaded, settings)
    }

    func testConcurrentSavesKeepASingleRow() async throws {
        // 50 concurrent saves must not create duplicate SettingsRecord rows
        // (WG-013 B1: the uniqueness constraint + last-writer-wins merge policy).
        let controller = try PersistenceController(inMemory: true)
        let repo = CoreDataSettingsRepository(controller)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    var settings = AppSettings.default
                    settings.analyticsEnabled = (index % 2 == 0)
                    try? await repo.save(settings)
                }
            }
            for await _ in group {}
        }

        let context = controller.container.newBackgroundContext()
        let count = try await context.perform {
            try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "SettingsRecord"))
        }
        XCTAssertEqual(count, 1, "concurrent saves must not duplicate the singleton row")

        // Reads are consistent — a single deterministic row, no stale duplicates.
        let first = try await repo.settings()
        let second = try await repo.settings()
        XCTAssertEqual(first, second)
    }
}
