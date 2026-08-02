import SwiftUI

/// Application entry point and composition root (WG-018).
///
/// The production dependency graph is built **once** here and injected into the
/// SwiftUI environment; feature screens read their repositories, clock, and id
/// generator from `\.appEnvironment` — never a global locator. If persistence
/// cannot load, the app shows an honest error rather than running without durable
/// alarm storage.
@main
struct WakeGuardApp: App {
    private let composition: Result<AppEnvironment, Error>

    init() {
        // Builds the on-disk Core Data graph synchronously on the main actor at
        // launch. For the small alarm/audit/outbox store this is sub-millisecond; the
        // only watchdog risk is a future heavyweight migration on a large store —
        // revisit with WG-017. Accepted MVP tradeoff.
        composition = Result { try AppEnvironment.production() }
    }

    var body: some Scene {
        WindowGroup {
            switch composition {
            case .success(let environment):
                RootView().environment(\.appEnvironment, environment)
            case .failure(let error):
                CompositionErrorView(error: error)
            }
        }
    }
}
