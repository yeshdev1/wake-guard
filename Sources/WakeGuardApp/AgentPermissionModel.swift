import Foundation
import Observation

/// Drives the agent-permission Settings row (WG-171): loads the current mode, offers only the
/// **selectable** modes (recommend-only / ask-before-acting — never auto-adjust in the MVP), and persists a
/// change through the `SettingsRepository`. It changes only the advisory-agent autonomy setting; it holds
/// **no alarm authority** and never weakens the rule that a critical alarm requires confirmation (#6).
@MainActor
@Observable
final class AgentPermissionModel {
    private(set) var mode: AgentPermissionMode = .recommendOnly
    private(set) var saveDidFail = false

    /// Only the MVP-selectable modes are offered; `autoAdjust` is never presented.
    let selectableModes = AgentPermissionMode.selectable

    private let repository: any SettingsRepository

    init(repository: any SettingsRepository) {
        self.repository = repository
    }

    func load() async {
        mode = (try? await repository.settings())?.agentPermissionMode ?? .recommendOnly
    }

    /// Persist a new mode. A non-selectable mode (auto-adjust) is **rejected** — the UI can never enable it.
    func setMode(_ newMode: AgentPermissionMode) async {
        guard newMode.isSelectable else { return }
        do {
            var settings = try await repository.settings()
            settings.agentPermissionMode = newMode
            try await repository.save(settings)
            mode = newMode
            saveDidFail = false
        } catch {
            saveDidFail = true
        }
    }
}
