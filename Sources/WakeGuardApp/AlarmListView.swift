import SwiftUI

/// The alarm list and next-alarm summary (WG-041) — the app's home screen. Reads its
/// repository and clock from the composed environment; if the environment is not composed
/// (`nil`), it shows an explicit safe state rather than a silent "no alarms" render, so a
/// storage failure is never mistaken for an empty schedule (WG-018 contract, #10). The
/// nil-environment path is defensive: the app shell (`WakeGuardApp`) normally intercepts a
/// composition failure with `CompositionErrorView`, but the environment key defaults to
/// `nil`, and previews/tests mount this screen without a graph.
struct AlarmListView: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        NavigationStack {
            content.navigationTitle("Alarms")
        }
    }

    @ViewBuilder private var content: some View {
        if let environment {
            AlarmListScreen(alarms: environment.alarmRepository, clock: environment.clock)
        } else {
            AlarmListMessageView(
                systemImage: "externaldrive.badge.exclamationmark", title: "Alarms unavailable",
                message: "WakeGuard couldn’t open local storage, so your alarms aren’t loaded. "
                    + "Reopen the app to try again.", identifier: "alarmListUnavailable")
        }
    }
}

/// Owns the view model and renders each state. Reloads on appear **and on every foreground**
/// so the next-ring time never goes stale after an alarm fires. A reconciliation pass shows
/// a non-blocking banner over the current content, never a blanking state.
private struct AlarmListScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AlarmListViewModel

    init(alarms: any AlarmRepository, clock: any WallClock) {
        _model = State(wrappedValue: AlarmListViewModel(alarms: alarms, clock: clock))
    }

    var body: some View {
        stateContent
            .task { await model.load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.load() } }
            }
            .safeAreaInset(edge: .top) {
                if model.isReconciling { ReconcilingBanner() }
            }
    }

    @ViewBuilder private var stateContent: some View {
        switch model.state {
        case .loading:
            AlarmListMessageView(
                progress: true, title: "Loading your alarms", message: "",
                identifier: "alarmListLoading")
        case .empty:
            AlarmListMessageView(
                systemImage: "alarm", title: "No alarms yet",
                message: "Alarms you create will appear here.", identifier: "alarmListEmpty")
        case .loaded(let content):
            AlarmListLoadedView(content: content)
        case .failed(let reason):
            AlarmListMessageView(
                systemImage: "exclamationmark.triangle", title: "Couldn’t load alarms",
                message: reason, identifier: "alarmListError")
        }
    }
}

/// A non-blocking banner shown while reconciliation runs (WG-029) — the alarm list stays
/// visible beneath it, so the user always sees their known alarms.
private struct ReconcilingBanner: View {
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ProgressView().controlSize(.small)
            Text("Checking your alarms…").font(DesignSystem.Typography.secondary)
            Spacer()
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.Colors.surface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking your alarms")
        .accessibilityIdentifier("reconcilingBanner")
    }
}

/// The loaded list: a prominent next-alarm summary section, then every alarm. `List`
/// sections give VoiceOver a logical reading order (summary before the full list).
private struct AlarmListLoadedView: View {
    let content: AlarmListContent

    var body: some View {
        List {
            Section("Next alarm") {
                NextAlarmSummary(item: content.nextAlarm)
            }
            Section("All alarms") {
                ForEach(content.items) { AlarmRow(item: $0) }
            }
        }
        .accessibilityIdentifier("alarmList")
    }
}

/// The soonest upcoming alarm, shown large. Reflows to vertical at large text sizes so the
/// time is never truncated. Falls back to an explicit "no upcoming" line.
private struct NextAlarmSummary: View {
    let item: AlarmListItem?

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(item.nextRingText).font(DesignSystem.Typography.sectionTitle)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        labelText(item)
                        Spacer(minLength: DesignSystem.Spacing.sm)
                        StatusBadge(style: item.status)
                    }
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        labelText(item)
                        StatusBadge(style: item.status)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.accessibilityLabel)
            .accessibilityIdentifier("nextAlarmSummary")
        } else {
            Text("No upcoming alarms")
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("noUpcomingAlarm")
        }
    }

    private func labelText(_ item: AlarmListItem) -> some View {
        Text(item.label).font(DesignSystem.Typography.secondary)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
    }
}

/// One alarm row: label + next-ring and a status badge, spoken as a single combined
/// VoiceOver phrase. Reflows to vertical at large text sizes so nothing truncates.
private struct AlarmRow: View {
    let item: AlarmListItem

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                labelStack
                Spacer(minLength: DesignSystem.Spacing.sm)
                StatusBadge(style: item.status)
            }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                labelStack
                StatusBadge(style: item.status)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityIdentifier("alarmRow")
    }

    @ViewBuilder private var labelStack: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
            Text(item.label).font(DesignSystem.Typography.cardTitle)
            Text(item.nextRingText).font(DesignSystem.Typography.secondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
    }
}

/// A centered message state (loading / empty / error / unavailable). One combined
/// accessibility element with a stable identifier for UI tests.
private struct AlarmListMessageView: View {
    var progress = false
    var systemImage: String?
    let title: String
    let message: String
    let identifier: String

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            if progress {
                ProgressView()
            } else if let systemImage {
                Image(systemName: systemImage).font(.largeTitle)
                    .foregroundStyle(DesignSystem.Colors.secondaryText).accessibilityHidden(true)
            }
            Text(title).font(DesignSystem.Typography.sectionTitle)
            if !message.isEmpty {
                Text(message).font(DesignSystem.Typography.secondary)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Previews

extension AlarmListContent {
    /// Illustrative sample content for previews (no repository/disk). The `nextRingText`
    /// mirrors the relative form the view model produces.
    fileprivate static let preview: AlarmListContent = {
        let wake = AlarmListItem(
            id: AlarmID(UUID()), label: "Wake up", isEnabled: true, isCritical: false,
            status: .scheduled, nextOccurrence: Date(timeIntervalSince1970: 1_700_000_000),
            nextRingText: "Tomorrow, 7:00 AM",
            accessibilityLabel: "Wake up, Scheduled, Tomorrow, 7:00 AM")
        let medication = AlarmListItem(
            id: AlarmID(UUID()), label: "Medication", isEnabled: true, isCritical: true,
            status: .critical, nextOccurrence: Date(timeIntervalSince1970: 1_700_030_000),
            nextRingText: "Tomorrow, 9:00 PM",
            accessibilityLabel: "Critical alarm. Medication, Critical, Tomorrow, 9:00 PM")
        let stale = AlarmListItem(
            id: AlarmID(UUID()), label: "Old reminder", isEnabled: true, isCritical: false,
            status: .attention, nextOccurrence: nil, nextRingText: "No upcoming time",
            accessibilityLabel: "Old reminder, Needs attention, No upcoming time")
        let off = AlarmListItem(
            id: AlarmID(UUID()), label: "Weekend lie-in", isEnabled: false, isCritical: false,
            status: .off, nextOccurrence: nil, nextRingText: "Off",
            accessibilityLabel: "Weekend lie-in, Off")
        return AlarmListContent(nextAlarm: wake, items: [wake, medication, stale, off])
    }()
}

#Preview("Loaded — light") {
    NavigationStack { AlarmListLoadedView(content: .preview).navigationTitle("Alarms") }
}

#Preview("Loaded — dark") {
    NavigationStack { AlarmListLoadedView(content: .preview).navigationTitle("Alarms") }
        .preferredColorScheme(.dark)
}

#Preview("Loaded — accessibility XL") {
    NavigationStack { AlarmListLoadedView(content: .preview).navigationTitle("Alarms") }
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Reconciling banner") {
    VStack(spacing: 0) {
        ReconcilingBanner()
        AlarmListLoadedView(content: .preview)
    }
}

#Preview("Empty") {
    AlarmListMessageView(
        systemImage: "alarm", title: "No alarms yet",
        message: "Alarms you create will appear here.", identifier: "alarmListEmpty")
}

#Preview("Error") {
    AlarmListMessageView(
        systemImage: "exclamationmark.triangle", title: "Couldn’t load alarms",
        message: "Your alarms couldn’t be loaded. They are still saved.",
        identifier: "alarmListError")
}
