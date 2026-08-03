import Foundation

@testable import WakeGuard

/// A fake `SettingsOpener` for the authorization-flow tests: records how many times
/// Settings was opened and returns a configurable result. Thread-safe via
/// `Synchronized`, so it is `Sendable`.
final class FakeSettingsOpener: SettingsOpener {
    private struct State: Sendable {
        var openResult: Bool
        var openCount = 0
    }

    private let state: Synchronized<State>

    init(openResult: Bool = true) {
        state = Synchronized(State(openResult: openResult))
    }

    var openCount: Int { state.get().openCount }

    func openAppSettings() async -> Bool {
        state.mutate { store in
            store.openCount += 1
            return store.openResult
        }
    }
}
