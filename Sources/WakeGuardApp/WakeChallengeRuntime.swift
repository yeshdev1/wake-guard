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
    private let alarmID: AlarmID
    private let required: Int
    private let pedometer: any PedometerSource
    private let coordinator: ChallengeStopCoordinator
    /// Records the wake's outcome into the on-device activity history (WG-299) — advisory, best-effort,
    /// off the alarm path (#8/#9). Optional so previews / hermetic tests can omit it.
    private let activityRecorder: (any AlarmActivityRecording)?
    private let now: @Sendable () -> Date
    private var startedAt: Date?
    private var observations: [MovementObservation] = []
    private var task: Task<Void, Never>?
    /// The in-flight authorized-stop submission after a pass (WG-295 D7) — unstructured so the view's
    /// dismissal (which cancels `task`) can never cancel the stop itself. Never cancelled by `stop()`.
    private(set) var passSubmission: Task<Void, Never>?
    /// The in-flight activity record — unstructured (never cancelled by `stop()`) and exposed so tests can
    /// await it.
    private(set) var activitySubmission: Task<Void, Never>?
    #if DEBUG
        /// Live anti-shake cadence stats for on-device calibration (WG-075) — DEBUG only, compiled out of
        /// Release; read by the diagnostics overlay on the challenge screen.
        private(set) var cadenceDebug: CadenceDiagnostics?
    #endif

    init(
        alarmID: AlarmID, required: Int, pedometer: any PedometerSource,
        processor: any AlarmCommandProcessing,
        activityRecorder: (any AlarmActivityRecording)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        viewModel = ChallengeViewModel(required: required)
        self.alarmID = alarmID
        self.required = required
        self.pedometer = pedometer
        self.activityRecorder = activityRecorder
        self.now = now
        coordinator = ChallengeStopCoordinator(alarmID: alarmID, processor: processor)
    }

    /// Record the wake's outcome into the activity history (WG-299). Fire-and-forget on an unstructured
    /// task so it never blocks the UI or gets cancelled by the view's teardown; at most one record fires.
    private func recordActivity(_ outcome: AlarmActivityOutcome) {
        guard let activityRecorder, let startedAt, activitySubmission == nil else { return }
        let activity = AlarmActivity(
            alarmID: alarmID, occurredAt: startedAt, outcome: outcome, walkRequired: true,
            stepsWalked: viewModel.stepsCompleted, requiredSteps: required,
            durationSeconds: max(0, Int(now().timeIntervalSince(startedAt))))
        activitySubmission = Task { await activityRecorder.record(activity) }
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
        recordActivity(.tapAlternative)
    }

    /// Consume the pedometer stream and drive the machine; on a pass, submit the authorized stop. Exposed
    /// (not `private`) so a test can drive it deterministically; production calls it via `start()`.
    func drive() async {
        startedAt = now()
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
                    // Submit the stop OUTSIDE this task (WG-295 D7): the pass dismisses the view, whose
                    // onDisappear cancels this task — an in-task await here could cancel the very
                    // submission that stops the ring. An unstructured task survives the dismissal; the
                    // handle is kept so tests (and any caller) can await the submission.
                    let coordinator = self.coordinator
                    passSubmission = Task { await coordinator.walkChallengeReached(.passed) }
                    recordActivity(.walkedAndPassed)
                    return
                }
            }
            // A cancelled consume (`stop()` / view teardown) is NOT an outcome — never write a terminal
            // phase into a machine that may still be displayed (WG-295, UI finding 2).
            guard !Task.isCancelled else { return }
            // The stream ended without a corroborated pass — the walk didn't complete in the window.
            if viewModel.machine.phase != .passed {
                viewModel.apply(.timeout)
                recordActivity(.timedOut)
            }
        } catch {
            guard !Task.isCancelled else { return }
            // The sensor dropped out mid-attempt — keep the alarm active, offer the fallback (#21).
            if viewModel.machine.phase != .passed {
                viewModel.apply(.sensorsUnavailable)
                recordActivity(.interrupted)
            }
        }
    }
}
