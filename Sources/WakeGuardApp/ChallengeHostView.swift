import SwiftUI

/// Hosts a live wake challenge (WG-073 CONNECT): it starts the `WakeChallengeRuntime` (live pedometer →
/// anti-shake machine → authorized stop), shows the walk `ChallengeView`, and offers the accessible
/// non-walking alternative — so no one is trapped (#21/#22). It dismisses when the challenge passes.
///
/// Reached today from a user-initiated "test the walk challenge" affordance (#18 requires an explicit
/// start); wiring it to a genuine unattended AlarmKit ring is device-only (WG-030).
struct ChallengeHostView: View {
    let runtime: WakeChallengeRuntime
    @State private var showingAccessible = false
    @State private var accessible: AccessibleChallengeViewModel
    @Environment(\.dismiss) private var dismiss

    init(runtime: WakeChallengeRuntime) {
        self.runtime = runtime
        _accessible = State(
            wrappedValue: AccessibleChallengeViewModel(
                requirements: AccessibleChallengeRequirements(kind: .tapSequence)))
    }

    var body: some View {
        ChallengeView(
            viewModel: runtime.viewModel,
            onUseAccessibleAlternative: { showingAccessible = true }
        )
        .task { runtime.start() }
        .onDisappear { runtime.stop() }
        .onChange(of: runtime.viewModel.machine.phase) { _, phase in
            // A genuine pass stopped the alarm — close the challenge.
            if phase == .passed { dismiss() }
        }
        .sheet(isPresented: $showingAccessible) {
            AccessibleChallengeView(viewModel: accessible)
                .onAppear {
                    accessible.onPassed = {
                        Task {
                            await runtime.accessibleAlternativePassed()
                            showingAccessible = false
                            dismiss()
                        }
                    }
                }
        }
        #if DEBUG
            .overlay(alignment: .top) { cadenceDebugReadout }
        #endif
        .accessibilityIdentifier("challengeHost")
    }

    #if DEBUG
        /// On-device anti-shake calibration readout (WG-075) — DEBUG only. Live interval count vs the
        /// required minimum, coefficient of variation vs the plausible-gait band, mean pace, and verdict —
        /// so a real walk and a shake can be compared to set the thresholds.
        @ViewBuilder private var cadenceDebugReadout: some View {
            if runtime.cadenceDebug != nil {
                Text(cadenceDebugText)
                    .font(DesignSystem.Typography.caption)
                    .padding(DesignSystem.Spacing.xs)
                    .background(.thinMaterial, in: .capsule)
                    .padding(.top, DesignSystem.Spacing.xs)
            }
        }

        private var cadenceDebugText: String {
            guard let stats = runtime.cadenceDebug else { return "" }
            let cov = stats.coefficientOfVariation.formatted(.number.precision(.fractionLength(2)))
            let pace = stats.meanSecondsPerStep.formatted(.number.precision(.fractionLength(2)))
            let minIntervals = CadenceThresholds.default.minimumIntervals
            return "int \(stats.intervalCount)/\(minIntervals) · CoV \(cov) · s/step \(pace) · "
                + stats.verdict.rawValue
        }
    #endif
}

/// Identifies the alarm whose walk challenge is being tested — drives the full-screen cover.
struct ChallengeTarget: Identifiable {
    let id: AlarmID
    let requiredSteps: Int
}

/// Reads the composed environment and hosts a live challenge test for one alarm (WG-073). Renders a safe
/// state if the environment is missing.
struct ChallengeTestCover: View {
    let alarmID: AlarmID
    let required: Int
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        if let environment {
            ChallengeRuntimeHost(
                alarmID: alarmID, required: required,
                pedometer: environment.pedometerLiveSource,
                processor: environment.alarmCommandProcessor)
        } else {
            ContentUnavailableView("Challenge unavailable", systemImage: "figure.walk")
                .accessibilityIdentifier("challengeUnavailable")
        }
    }
}

/// Owns the `WakeChallengeRuntime` in `@State` (built once from the injected ports) so it survives
/// re-renders, then shows the challenge host.
private struct ChallengeRuntimeHost: View {
    @State private var runtime: WakeChallengeRuntime

    init(
        alarmID: AlarmID, required: Int, pedometer: any PedometerSource,
        processor: any AlarmCommandProcessing
    ) {
        _runtime = State(
            wrappedValue: WakeChallengeRuntime(
                alarmID: alarmID, required: required, pedometer: pedometer, processor: processor))
    }

    var body: some View { ChallengeHostView(runtime: runtime) }
}
