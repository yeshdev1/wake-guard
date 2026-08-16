import SwiftUI

/// The sleep-readiness screen (WG-131/133 composition). It reads recent sleep from HealthKit — read-only,
/// on device, never stored raw (#41) — and shows a coarse readiness **estimate**, never a diagnosis (#39).
/// Health is optional (#36/#38): a denied grant or no data (e.g. in the simulator) degrades to
/// "not enough data" rather than blocking. Reached from the alarm list; requests Health access in context.
struct ReadinessScreen: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        if let environment {
            ReadinessScreenContent(sleepQuery: environment.sleepQuery, clock: environment.clock)
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

    init(sleepQuery: any SleepSampleQuerying, clock: any WallClock) {
        _model = State(wrappedValue: ReadinessViewModel(sleepQuery: sleepQuery))
        self.clock = clock
    }

    var body: some View {
        ScrollView {
            if let assessment = model.assessment {
                ReadinessCardView(
                    assessment: assessment, interruptions: model.lastNightInterruptions
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
