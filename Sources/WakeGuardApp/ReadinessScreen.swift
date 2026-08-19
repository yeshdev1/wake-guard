import SwiftUI

/// The sleep-readiness screen (WG-131/133 composition). It reads recent sleep from HealthKit — read-only,
/// on device, never stored raw (#41) — and shows a coarse readiness **estimate**, never a diagnosis (#39).
/// Health is optional (#36/#38): a denied grant or no data (e.g. in the simulator) degrades to
/// "not enough data" rather than blocking. Reached from the alarm list; requests Health access in context.
struct ReadinessScreen: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        if let environment {
            ReadinessScreenContent(
                sleepQuery: environment.sleepQuery,
                motionHistory: environment.motionActivityHistory, clock: environment.clock)
        } else {
            ContentUnavailableView("Readiness unavailable", systemImage: "bed.double")
                .accessibilityIdentifier("readinessUnavailable")
        }
    }
}

/// Owns the `ReadinessViewModel` in `@State` (built once from the injected sleep source) so it survives
/// re-renders, requests Health access on appear, and renders the readiness card (or its degraded state).
private struct ReadinessScreenContent: View {
    @State private var model: ReadinessViewModel
    private let clock: any WallClock

    init(
        sleepQuery: any SleepSampleQuerying, motionHistory: any MotionActivityHistorySource,
        clock: any WallClock
    ) {
        // The motion-history source is injected from the composed environment (WG-310) so the readiness
        // screen can show a motion-based estimate alongside any HealthKit sleep data (WG-312). The in-memory
        // graph injects `FixtureMotionActivityHistory`, which returns a scripted night, so previews and the
        // screenshot tour document the section's real appearance rather than a hardware-absence claim about
        // the reader's device. On a denied grant, absent hardware or a failed read the section still renders
        // and states the reason (WG-318); it is never hidden.
        _model = State(
            wrappedValue: ReadinessViewModel(sleepQuery: sleepQuery, motionHistory: motionHistory))
        self.clock = clock
    }

    var body: some View {
        ScrollView {
            if let assessment = model.assessment {
                ReadinessCardView(
                    assessment: assessment, interruptions: model.lastNightInterruptions,
                    movement: model.movement
                )
                .padding(DesignSystem.Spacing.lg)
            } else {
                ProgressView("Checking your sleep readiness…")
                    .padding(DesignSystem.Spacing.xl)
                    .accessibilityIdentifier("readinessLoading")
            }
        }
        .navigationTitle("Readiness")
        .task {
            // Request Health read access in context, then compute. On the simulator / an ineligible
            // device there is no sleep data → the card degrades to "not enough data" (#36/#38).
            _ = await HealthAuthorizationCoordinator(provider: HealthKitAuthorizationAdapter())
                .requestAccess()
            await model.refresh(now: clock.now)
        }
    }
}
