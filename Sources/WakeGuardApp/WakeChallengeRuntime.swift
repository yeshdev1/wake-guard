import Foundation
import Observation

/// Drives a live wake challenge end-to-end (WG-073 CONNECT): it consumes the **live pedometer**, fuses each
/// sample into the deterministic `WakeChallengeMachine` via `ChallengeObservationReducer` (so the anti-shake
/// corroboration gate applies, #19/#20), and on a genuine pass submits **exactly one** authorized ring-stop
/// through `ChallengeStopCoordinator` → `AlarmCommandProcessing` (#2/#24). Sensor unavailability or a
/// dropped stream leaves the alarm active and offers the accessible alternative (#21) — a movement
/// inference alone never stops the alarm.
///
/// It presents `ChallengeViewModel`; it holds no alarm authority beyond the single authorized pass. The
/// production trigger is a user-initiated "test the walk challenge" affordance (#18 requires an explicit
/// start); wiring it to a genuine unattended AlarmKit ring is device-only (WG-030) and out of scope here.
@MainActor
@Observable
final class WakeChallengeRuntime {
    let viewModel: ChallengeViewModel
    private let pedometer: any PedometerSource
    private let coordinator: ChallengeStopCoordinator
    private var observations: [MovementObservation] = []
    private var task: Task<Void, Never>?
    #if DEBUG
        /// Live anti-shake cadence stats for on-device calibration (WG-075) — DEBUG only, compiled out of
        /// Release; read by the diagnostics overlay on the challenge screen.
        private(set) var cadenceDebug: CadenceDiagnostics?
    #endif

    init(
        alarmID: AlarmID, required: Int, pedometer: any PedometerSource,
        processor: any AlarmCommandProcessing
    ) {
        viewModel = ChallengeViewModel(required: required)
        self.pedometer = pedometer
        coordinator = ChallengeStopCoordinator(alarmID: alarmID, processor: processor)
    }

    /// Begin the challenge in a background task (production). Idempotent.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.drive() }
    }

    /// Stop consuming the pedometer (cancels the stream, which stops CoreMotion). Does not dismiss the
    /// alarm — only a genuine pass does that.
    func stop() {
        task?.cancel()
        task = nil
    }

    /// The user completed the accessible non-walking alternative — the authorized fallback (#22). Submits
    /// exactly one stop.
    func accessibleAlternativePassed() async {
        await coordinator.accessibleAlternativePassed()
    }

    /// Consume the pedometer stream and drive the machine; on a pass, submit the authorized stop. Exposed
    /// (not `private`) so a test can drive it deterministically; production calls it via `start()`.
    func drive() async {
        viewModel.apply(.start)
        var availability = await pedometer.availability()
        if availability == .notAuthorized {
            // Motion & Fitness may just be not-yet-asked — trigger the system prompt in context (WG-061),
            // then re-read. A denial stays `.notAuthorized` → the accessible alternative (#21/#22).
            availability = await pedometer.requestAuthorization()
        }
        guard availability == .available else {
            viewModel.apply(.sensorsUnavailable)  // offer the accessible alternative (#21/#22)
            return
        }
        viewModel.apply(.sensorsReady)
        do {
            for try await sample in pedometer.samples() {
                observations.append(MovementObservation.from(pedometer: sample))
                #if DEBUG
                    cadenceDebug = CadenceRegularity.diagnose(observations)
                #endif
                viewModel.apply(ChallengeObservationReducer.event(from: observations))
                if viewModel.machine.phase == .passed {
                    await coordinator.walkChallengeReached(.passed)
                    return
                }
            }
            // The stream ended without a corroborated pass — the walk didn't complete in the window.
            if viewModel.machine.phase != .passed { viewModel.apply(.timeout) }
        } catch {
            // The sensor dropped out mid-attempt — keep the alarm active, offer the fallback (#21).
            if viewModel.machine.phase != .passed { viewModel.apply(.sensorsUnavailable) }
        }
    }
}
