import Observation

/// Drives the optional significant-location education + control (WG-109). It reads the current OS
/// authorization and the persisted `locationContextEnabled` control, exposes the education copy
/// (approximate purpose + battery behavior + works-without-permission), and lets the user enable or
/// **disable** monitoring. It holds **no alarm authority** and stores **no location data** — it reaches
/// only the settings and the (coarse) location source — so nothing here can affect whether an alarm
/// rings, and the app's time-zone travel detection (WG-100) runs regardless of this control or the OS
/// permission. `@MainActor` because it feeds SwiftUI directly.
@MainActor
@Observable
final class LocationMonitoringModel {
    /// The persisted control — whether the user has enabled significant-location monitoring. **Opt-in**
    /// (`false` until turned on). Reflects the **saved truth**: updated only on a successful save, so the
    /// toggle never silently diverges from storage.
    private(set) var isMonitoringEnabled = false
    /// The current OS authorization, or `nil` before the first `refresh()`.
    private(set) var authorizationStatus: LocationAuthorizationStatus?
    /// Set when the last save failed, so the UI can say "couldn't save" without misreporting the state.
    private(set) var saveDidFail = false

    /// The user-facing education copy (approximate purpose, battery behavior, works-without-permission).
    let education = LocationEducation.standard

    private let settings: any SettingsRepository
    private let locationSource: any SignificantLocationSource

    init(settings: any SettingsRepository, locationSource: any SignificantLocationSource) {
        self.settings = settings
        self.locationSource = locationSource
    }

    /// Read the persisted control + current authorization, **without prompting**. Safe on appear and on
    /// every foreground so the control reflects a change the user made in Settings.
    func refresh() async {
        authorizationStatus = await locationSource.authorizationStatus()
        if let current = try? await settings.settings() {
            isMonitoringEnabled = current.locationContextEnabled
        }
    }

    /// Enable or **disable** monitoring, persisting the control (available regardless of OS permission —
    /// the user can always turn the app's monitoring off). On a save failure the shown state is left at
    /// the persisted truth and `saveDidFail` is set — the toggle never silently diverges from storage.
    func setMonitoringEnabled(_ enabled: Bool) async {
        do {
            var current = try await settings.settings()
            current.locationContextEnabled = enabled
            try await settings.save(current)
            isMonitoringEnabled = enabled
            saveDidFail = false
        } catch {
            saveDidFail = true
        }
    }
}
