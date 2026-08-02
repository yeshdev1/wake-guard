import SwiftUI

private struct AppEnvironmentKey: EnvironmentKey {
    // Default `nil` = "not composed". A non-optional *fataling* default was tried and
    // rejected: SwiftUI evaluates a custom key's default during scene setup at app
    // launch, so a `fatalError` there crashes the app / test host even when the graph
    // is correctly injected. So the value is optional — and every consumer MUST
    // render an explicit safe state when it is nil (e.g. a storage-unavailable
    // screen), never a silent empty-success render that would falsely show "no
    // alarms" (WG-018).
    static let defaultValue: AppEnvironment? = nil
}

extension EnvironmentValues {
    /// The composed dependency graph, injected once at the app root by
    /// `WakeGuardApp`. `nil` means "not composed"; a consumer that finds it nil must
    /// present an explicit safe state, never render as if there were no alarms.
    /// Screens read their ports from here via `@Environment` — never a global locator.
    var appEnvironment: AppEnvironment? {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
