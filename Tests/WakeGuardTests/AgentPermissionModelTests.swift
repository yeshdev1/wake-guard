import Foundation
import XCTest

@testable import WakeGuard

/// WG-171: the agent-permission Settings view-model. Verifies it loads and persists the mode, offers only
/// the selectable modes, and **rejects auto-adjust** (the UI can never enable it).
@MainActor
final class AgentPermissionModelTests: XCTestCase {

    private func repository(_ mode: AgentPermissionMode) -> InMemorySettingsRepository {
        var settings = AppSettings.default
        settings.agentPermissionMode = mode
        return InMemorySettingsRepository(settings)
    }

    func testLoadReadsPersistedMode() async {
        let model = AgentPermissionModel(repository: repository(.askBeforeActing))
        await model.load()
        XCTAssertEqual(model.mode, .askBeforeActing)
    }

    func testSetModePersistsAndUpdates() async throws {
        let repository = repository(.recommendOnly)
        let model = AgentPermissionModel(repository: repository)
        await model.setMode(.askBeforeActing)
        XCTAssertEqual(model.mode, .askBeforeActing)
        let stored = try await repository.settings().agentPermissionMode
        XCTAssertEqual(stored, .askBeforeActing)
        XCTAssertFalse(model.saveDidFail)
    }

    func testSetModeRejectsAutoAdjust() async throws {
        let repository = repository(.recommendOnly)
        let model = AgentPermissionModel(repository: repository)
        await model.setMode(.autoAdjust)
        XCTAssertEqual(model.mode, .recommendOnly, "auto-adjust must never be selectable")
        let stored = try await repository.settings().agentPermissionMode
        XCTAssertEqual(stored, .recommendOnly)
    }

    func testSaveFailureSetsFlag() async {
        let model = AgentPermissionModel(repository: FailingSettingsRepository())
        await model.setMode(.askBeforeActing)
        XCTAssertTrue(model.saveDidFail)
    }

    func testSelectableModesExcludeAutoAdjust() {
        let model = AgentPermissionModel(repository: repository(.recommendOnly))
        XCTAssertFalse(model.selectableModes.contains(.autoAdjust))
    }
}

/// A `SettingsRepository` whose `save` always fails — to exercise the save-error path.
private struct FailingSettingsRepository: SettingsRepository {
    func settings() async throws -> AppSettings { .default }
    func save(_ settings: AppSettings) async throws { throw CocoaError(.fileWriteUnknown) }
}
