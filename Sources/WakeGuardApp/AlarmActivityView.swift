import SwiftUI

/// The "Alarm Activity" section (WG-299): a plain-English summary of recent wakes, then a card per rung
/// alarm's challenge — walk or not, steps, duration, outcome. All text is on-device (the AI narration is
/// generated and cached on device, #35/#40) and grounded in recorded facts (#32); it makes no health or
/// diagnostic claim (#39). Reads the activity store from the composed environment; a nil environment shows
/// an explicit safe state rather than an empty list.
struct AlarmActivityView: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        Group {
            if let environment {
                AlarmActivityScreen(
                    store: environment.alarmActivityStore,
                    narrator: AlarmActivityNarrator(
                        generator: ExplanationGenerator(
                            generator: StructuredGenerator(
                                provider: environment.languageModelProvider))),
                    clock: environment.clock)
            } else {
                AlarmListMessageView(
                    systemImage: "externaldrive.badge.exclamationmark",
                    title: "Activity unavailable",
                    message: "Alarm Agent couldn’t open local storage, so your wake activity isn’t "
                        + "available. Reopen the app to try again.",
                    identifier: "activityUnavailable")
            }
        }
        .navigationTitle("Alarm Activity")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AlarmActivityScreen: View {
    @State private var model: AlarmActivityViewModel
    private let clock: any WallClock

    init(store: any AlarmActivityStore, narrator: AlarmActivityNarrator, clock: any WallClock) {
        _model = State(wrappedValue: AlarmActivityViewModel(store: store, narrator: narrator))
        self.clock = clock
    }

    var body: some View {
        content.task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        if !model.hasLoaded {
            AlarmListMessageView(
                progress: true, title: "Loading your activity…", message: "",
                identifier: "activityLoading")
        } else if model.entries.isEmpty {
            AlarmListMessageView(
                systemImage: "figure.walk.motion", title: "No wakes yet",
                message: "Once an alarm rings and you complete its walk, it'll appear here.",
                identifier: "activityEmpty")
        } else {
            loaded
        }
    }

    private var loaded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                summaryCard
                ForEach(Array(model.entries.enumerated()), id: \.offset) { _, entry in
                    activityCard(entry)
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .accessibilityIdentifier("activityList")
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Your recent wakes")
                .font(DesignSystem.Typography.cardTitle)
            Text(model.summary)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(
            DesignSystem.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card)
        )
        .accessibilityIdentifier("activitySummary")
    }

    private func activityCard(_ entry: AlarmActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Label {
                Text(entry.activity.occurredAt, format: .dateTime.weekday().hour().minute())
            } icon: {
                Image(systemName: icon(for: entry.activity.outcome))
            }
            .font(DesignSystem.Typography.secondary)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            Text(entry.summary)
                .font(DesignSystem.Typography.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(
            DesignSystem.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card)
        )
        .accessibilityIdentifier("activityCard")
    }

    private func icon(for outcome: AlarmActivityOutcome) -> String {
        switch outcome {
        case .walkedAndPassed: "checkmark.circle"
        case .tapAlternative: "hand.tap"
        case .timedOut: "clock.badge.exclamationmark"
        case .interrupted: "exclamationmark.triangle"
        }
    }
}
