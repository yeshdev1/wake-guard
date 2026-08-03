import Foundation

/// The next step the UI should take to obtain (or recover) authorization to schedule
/// system alarms (WG-025). A closed, `Equatable` outcome so the flow is deterministic
/// and testable.
enum AlarmAuthorizationStep: Sendable, Equatable {
    /// Not yet determined — show the permission explanation, *then* request. The
    /// system dialog must never appear unexplained (acceptance: explanation precedes
    /// request).
    case explainThenRequest
    /// Authorized — proceed to schedule.
    case authorized
    /// Denied — recoverable in Settings; offer the deep link.
    case deniedOpenSettings
    /// Restricted by policy / parental controls — a Settings link cannot change it,
    /// so fall back to a non-AlarmKit path and keep existing alarms (#10).
    case restrictedUseFallback
    /// The state is unknown (the request threw or was interrupted). Preserve the last
    /// safe alarm and let the user retry — never treat this as a denial (#10).
    case unknownKeepSafe
}

/// Opens the app's system Settings page (for permission recovery). A port so the
/// authorization flow stays framework-independent; the real UIKit-backed opener is
/// supplied by the app shell, and tests use a fake.
protocol SettingsOpener: Sendable {
    /// Open the app's Settings page; returns whether it was opened.
    func openAppSettings() async -> Bool
}

/// Orchestrates AlarmKit authorization (WG-025) around the `AlarmManagerAdapter`
/// primitive: the system prompt is preceded by an explanation, and denied/restricted
/// states are recoverable.
///
/// It is **read-only with respect to alarms**: it invokes no mutating adapter method
/// (only `authorizationState` / `requestAuthorization`), so a denial — or any
/// non-authorized outcome — can never drop a scheduled alarm; the caller simply keeps
/// its existing alarms (#10). It *holds* an `AlarmManagerAdapter` (which can mutate),
/// so this is enforced by `testFlowNeverMutatesAlarms`, not by capability confinement
/// — the single-target build has no finer access boundary. The concrete adapter
/// remains the only component that talks to AlarmKit (#1).
struct AlarmAuthorizationCoordinator: Sendable {
    private let adapter: any AlarmManagerAdapter
    private let settingsOpener: any SettingsOpener

    init(adapter: any AlarmManagerAdapter, settingsOpener: any SettingsOpener) {
        self.adapter = adapter
        self.settingsOpener = settingsOpener
    }

    /// The step for the *current* authorization state, **without prompting**. A
    /// not-determined state routes through the explanation first, so reading the step
    /// never triggers the system dialog.
    func currentStep() async -> AlarmAuthorizationStep {
        step(for: await adapter.authorizationState(), afterRequest: false)
    }

    /// Perform the system authorization request — call this only *after* the
    /// explanation has been shown (acceptance: explanation precedes request). The flow
    /// routes `.notDetermined` through `.explainThenRequest` precisely so a correct
    /// caller passes through the explanation first; **displaying** it and gating this
    /// call is the permission-UI's contract — the flow cannot observe whether a screen
    /// was shown (DECISIONS WG-025). A thrown or interrupted request leaves the state
    /// unknown → `.unknownKeepSafe`, never an assumed denial that would weaken a
    /// critical alarm (#10).
    func requestAfterExplanation() async -> AlarmAuthorizationStep {
        do {
            return step(for: try await adapter.requestAuthorization(), afterRequest: true)
        } catch {
            return .unknownKeepSafe
        }
    }

    /// Open the app's Settings page — only where appropriate. Denial is recoverable
    /// there; a restriction is not (a Settings link cannot change a policy control),
    /// and authorized / not-determined do not need it — so this no-ops and returns
    /// `false` for any non-denied state. It re-reads the current step at call time, so
    /// if the user granted access between seeing the button and tapping it, Settings is
    /// (correctly) not opened.
    @discardableResult
    func openSettingsIfAppropriate() async -> Bool {
        guard case .deniedOpenSettings = await currentStep() else { return false }
        return await settingsOpener.openAppSettings()
    }

    private func step(
        for state: AlarmAuthorizationState, afterRequest: Bool
    ) -> AlarmAuthorizationStep {
        switch state {
        case .authorized: return .authorized
        case .denied: return .deniedOpenSettings
        case .restricted: return .restrictedUseFallback
        case .notDetermined: return afterRequest ? .unknownKeepSafe : .explainThenRequest
        }
    }
}
