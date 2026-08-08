import Foundation

@testable import WakeGuard

/// A configurable `AlarmCommandProcessing` for tests (WG-042/043): records every submitted
/// command and returns a set outcome. It can return a different outcome for confirmed vs
/// unconfirmed calls, so the critical-confirmation flow (#6) — submit → `.needsConfirmation`
/// → confirm → `.applied` — can be exercised without the real policy engine. Thread-safe.
final class FakeAlarmCommandProcessor: AlarmCommandProcessing {
    private struct State: Sendable {
        var unconfirmed: CommandOutcome
        var confirmed: CommandOutcome
        var seen: [AlarmCommand] = []
    }
    private let state: Synchronized<State>

    init(outcome: CommandOutcome = .uncertain) {
        state = Synchronized(State(unconfirmed: outcome, confirmed: outcome))
    }

    /// Distinct outcomes for the confirmation flow: an unconfirmed destructive command is
    /// rejected; the confirmed re-submit succeeds.
    init(unconfirmed: CommandOutcome, confirmed: CommandOutcome) {
        state = Synchronized(State(unconfirmed: unconfirmed, confirmed: confirmed))
    }

    /// Every command the caller submitted, in order.
    var seen: [AlarmCommand] { state.get().seen }

    func setOutcome(_ outcome: CommandOutcome) {
        state.mutate {
            $0.unconfirmed = outcome
            $0.confirmed = outcome
        }
    }

    func process(
        _ command: AlarmCommand, from source: CommandSource, by actor: AuditActor,
        userConfirmed: Bool
    ) async -> CommandOutcome {
        // A real suspension point, so a caller's `await process(...)` genuinely yields — this lets
        // concurrency tests exercise the actor reentrancy window around a caller's once-only guard.
        await Task.yield()
        return state.mutate { store in
            store.seen.append(command)
            return userConfirmed ? store.confirmed : store.unconfirmed
        }
    }
}
