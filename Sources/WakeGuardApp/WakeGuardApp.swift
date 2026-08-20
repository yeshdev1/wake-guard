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
        // UI tests (WG-050) launch with `-uiTesting` to run against an **isolated, empty
        // in-memory** store — never the on-disk production store, so a test run neither reads
        // nor writes the user's real alarms and each launch starts clean and deterministic.
        // Gated behind DEBUG so this test-only affordance is compiled out of release builds — it
        // can never be reached in a shipped app (launch args can't be injected there anyway).
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                // WG-322: `-uiTestingSleepReadFails` composes a sleep read that throws, which is the only
                // way the tour reaches the readiness card's `.unavailable` branch — the default graph's
                // `UnavailableSleepQuery` returns `[]`, a concluded read, so it lands in `.assessed`. That
                // branch is where the surviving M4 mutant lived and where no check observed the rendering.
                // Additive by design: absent this argument the graph is bit-for-bit what it was, so the
                // existing tour keeps documenting the success path.
                //
                // It is read *inside* the `-uiTesting` branch, so it does nothing on its own: a launch
                // passing only `-uiTestingSleepReadFails` gets the production on-disk graph and an ordinary
                // readiness card, not a failed read. Pass both, as `launch(sleepReadFails:)` does.
                let sleepReadFails = ProcessInfo.processInfo.arguments.contains(
                    "-uiTestingSleepReadFails")
                composition = Result {
                    try AppEnvironment.inMemory(
                        sleepQuery: sleepReadFails ? FailingSleepQuery() : UnavailableSleepQuery())
                }
                return
            }
        #endif
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
