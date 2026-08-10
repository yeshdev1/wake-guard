import Observation

/// Drives the alarm-authorization UI (WG-025 / runs-on-a-phone step 2) from the composed
/// `AlarmAuthorizationCoordinator`. It only *reads* the authorization state and *requests* it after
/// the explanation is shown — it holds no alarm-mutating capability, so a denial or an interrupted
/// request can never drop a scheduled alarm (#10); the worst case is a banner asking the user to try
/// again. `@MainActor` because it feeds SwiftUI directly.
@MainActor
@Observable
final class AlarmPermissionModel {
    /// The latest resolved step, or `nil` before the first `refresh()` (render nothing until known,
    /// so a not-yet-loaded state never flashes a misleading "needs permission" banner).
    private(set) var step: AlarmAuthorizationStep?

    private let coordinator: AlarmAuthorizationCoordinator

    init(coordinator: AlarmAuthorizationCoordinator) {
        self.coordinator = coordinator
    }

    /// Read the current authorization step **without prompting** — safe to call on appear and on
    /// every foreground so the banner reflects a change the user made in Settings.
    func refresh() async {
        step = await coordinator.currentStep()
    }

    /// Request authorization — call this only from the explanation's continue action, so the system
    /// dialog is always preceded by the explanation (WG-025). An interrupted/undetermined result maps
    /// to `.unknownKeepSafe`, never an assumed denial.
    func requestAfterExplanation() async {
        step = await coordinator.requestAfterExplanation()
    }

    /// Open Settings to recover a denial (no-ops for any non-denied state), then re-read the step so
    /// granting access in Settings clears the banner on return.
    func openSettings() async {
        _ = await coordinator.openSettingsIfAppropriate()
        await refresh()
    }
}
