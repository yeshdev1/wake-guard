import Foundation

@testable import WakeGuard

/// A configurable `AlarmPolicyEngine` for tests: authorizes by default (or rejects
/// with a set reason) and records every command it was asked to authorize, so tests
/// can assert that the processor routes all commands through authorization (#3).
/// Thread-safe via `Synchronized`.
final class FakeAlarmPolicyEngine: AlarmPolicyEngine {
    private struct State: Sendable {
        var decision: PolicyDecision
        var seen: [AlarmCommand] = []
    }

    private let state: Synchronized<State>

    init(decision: PolicyDecision = .authorized) {
        state = Synchronized(State(decision: decision))
    }

    func setDecision(_ decision: PolicyDecision) {
        state.mutate { $0.decision = decision }
    }

    /// Every command the processor asked to authorize, in order.
    var seenCommands: [AlarmCommand] { state.get().seen }

    func authorize(
        _ command: AlarmCommand, from source: CommandSource, userConfirmed: Bool
    ) async -> PolicyDecision {
        state.mutate { store in
            store.seen.append(command)
            return store.decision
        }
    }
}
