import Foundation
import Observation

/// Resolves a `DeepLinkRoute` into what the app should present (WG-049). It only **reads** the
/// alarm repository to check the target exists — it never mutates anything, so following a link
/// can only navigate, never change an alarm (#7). A stale/unknown id, an unsupported target, or a
/// transient read error each resolve to a safe, user-readable message rather than a wrong screen.
@MainActor
@Observable
final class DeepLinkModel {
    /// When set, present the edit screen for this alarm. Navigational only — the user's edits go
    /// through the command processor (gated for a critical alarm); opening the link mutates nothing.
    var alarmToEdit: Alarm?
    /// When set, show a safe error alert.
    var errorMessage: String?

    /// Monotonic request token: a later link supersedes an in-flight one, so a slow repository
    /// read can't present a screen for a link the user has already moved past.
    private var latestRequest = 0

    func open(_ route: DeepLinkRoute, using environment: AppEnvironment?) async {
        latestRequest += 1
        let request = latestRequest
        // Clear both fields up front so a prior link's screen/error can't linger under a new one.
        alarmToEdit = nil
        errorMessage = nil
        guard let environment else {
            set(error: "Alarm Agent isn’t ready yet. Please reopen the app and try again.", request)
            return
        }
        switch route {
        case .alarm(let id):
            await resolveAlarm(id, alarms: environment.alarmRepository, request: request)
        case .proposal:
            // AI suggestions have no review screen yet (E09) — never invent one, never act.
            set(error: "That suggestion isn’t available.", request)
        case .unknown:
            set(error: "That link couldn’t be opened.", request)
        }
    }

    private func resolveAlarm(_ id: AlarmID, alarms: any AlarmRepository, request: Int) async {
        do {
            let alarm = try await alarms.alarm(id: id)
            guard request == latestRequest else { return }  // superseded by a newer link
            if let alarm {
                alarmToEdit = alarm  // present the screen; nothing is changed
            } else {
                set(error: "That alarm no longer exists.", request)  // stale / unknown id
            }
        } catch {
            set(error: "We couldn’t open that alarm right now. Please try again.", request)
        }
    }

    /// Set the error only if this request is still the latest (not superseded).
    private func set(error message: String, _ request: Int) {
        guard request == latestRequest else { return }
        errorMessage = message
    }
}
