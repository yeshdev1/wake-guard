import Foundation
import Observation

/// Drives accountless local deletion (WG-184). The user can delete chosen **optional** categories (which
/// never touches alarms) or request a **full reset**. A full reset is gated behind an explicit
/// alarm-consequence confirmation — `requestFullReset()` only *arms* the confirmation; nothing is deleted
/// until `confirmFullReset()`. Holds no alarm authority; deletion runs through the coordinator + eraser.
@MainActor
@Observable
final class DataDeletionModel {
    var selectedOptional: Set<OptionalDataCategory> = []
    /// `true` once the user asks to delete all data — the view shows the alarm-consequence confirmation.
    private(set) var pendingFullResetConfirmation = false
    private(set) var lastOutcome: DeletionOutcome?

    private let coordinator: DeletionCoordinator

    init(coordinator: DeletionCoordinator) {
        self.coordinator = coordinator
    }

    var canDeleteSelected: Bool { !selectedOptional.isEmpty }

    /// Delete the selected optional categories. Safe — never affects alarms, so no confirmation is needed.
    func deleteSelectedOptional() async {
        guard !selectedOptional.isEmpty else { return }
        lastOutcome = await coordinator.delete(
            .optionalCategories(selectedOptional), userConfirmedAlarmConsequences: false)
        if lastOutcome == .deleted { selectedOptional = [] }
    }

    /// Arm the full-reset confirmation. Deletes nothing on its own.
    func requestFullReset() { pendingFullResetConfirmation = true }

    func cancelFullReset() { pendingFullResetConfirmation = false }

    /// Confirm and perform the full reset — this is the only path that erases alarms, and it passes the
    /// explicit alarm-consequence confirmation to the coordinator.
    func confirmFullReset() async {
        pendingFullResetConfirmation = false
        lastOutcome = await coordinator.delete(.allData, userConfirmedAlarmConsequences: true)
    }
}
