import UIKit

/// The real `SettingsOpener` (WG-025): opens the app's system Settings page so a user can
/// recover a **denied** AlarmKit permission. Lives in the composition/app-shell layer — the only
/// place UIKit is reached — so the authorization flow itself stays framework-independent and
/// testable with a fake. Read-only with respect to alarms.
struct UIKitSettingsOpener: SettingsOpener {
    func openAppSettings() async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                guard let url = URL(string: UIApplication.openSettingsURLString) else {
                    return continuation.resume(returning: false)
                }
                UIApplication.shared.open(url, options: [:]) { opened in
                    continuation.resume(returning: opened)
                }
            }
        }
    }
}

/// A no-op `SettingsOpener` for the in-memory (test/preview) graph: there is no app to route to
/// Settings, and a preview must never trigger a system navigation. Returns `false` ("not opened").
struct NoopSettingsOpener: SettingsOpener {
    func openAppSettings() async -> Bool { false }
}
