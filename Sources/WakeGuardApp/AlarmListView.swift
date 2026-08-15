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
            AlarmListScreen(
                alarms: environment.alarmRepository, clock: environment.clock,
                processor: environment.alarmCommandProcessor, ids: environment.identifierGenerator,
                schedulesInSystem: environment.schedulesAlarmsInSystem,
                authorizationCoordinator: environment.authorizationCoordinator,
                feedbackStore: environment.preAlarmFeedback)
        } else {
            AlarmListMessageView(
                systemImage: "externaldrive.badge.exclamationmark", title: "Alarms unavailable",
                message: "Alarm Agent couldn’t open local storage, so your alarms aren’t loaded. "
                    + "Reopen the app to try again.", identifier: "alarmListUnavailable")
        }
    }
}

/// The one modal the list can present (WG-297) — create, describe, or edit — driven through a single
/// `.sheet(item:)`. `Identifiable` by a stable key so re-presenting the same kind is a no-op.
private enum ActiveSheet: Identifiable {
    case create
    case describe
    case edit(Alarm)

    var id: String {
        switch self {
        case .create: "create"
        case .describe: "describe"
        case .edit(let alarm): "edit-\(alarm.id.rawValue.uuidString)"
        }
    }
}

/// Owns the view model and renders each state. Reloads on appear **and on every foreground**
/// so the next-ring time never goes stale after an alarm fires. A reconciliation pass shows
/// a non-blocking banner over the current content, never a blanking state.
private struct AlarmListScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AlarmListViewModel
    @State private var permission: AlarmPermissionModel
    /// One presentation at a time (WG-297): a single `.sheet(item:)` instead of three stacked `.sheet`
    /// modifiers, whose overlapping present/dismiss transitions could flash one sheet's content over
    /// another's. The challenge is a separate full-screen cover (a different presentation style).
    @State private var activeSheet: ActiveSheet?
    @State private var challengeTarget: ChallengeTarget?
    private let processor: any AlarmCommandProcessing
    private let clock: any WallClock
    private let ids: any IdentifierGenerator
    private let schedulesInSystem: Bool
    private let feedbackStore: any PreAlarmFeedbackStore

    init(
        alarms: any AlarmRepository, clock: any WallClock,
        processor: any AlarmCommandProcessing, ids: any IdentifierGenerator,
        schedulesInSystem: Bool,
        authorizationCoordinator: AlarmAuthorizationCoordinator,
        feedbackStore: any PreAlarmFeedbackStore
    ) {
        _model = State(
            wrappedValue: AlarmListViewModel(alarms: alarms, clock: clock, processor: processor))
        _permission = State(
            wrappedValue: AlarmPermissionModel(coordinator: authorizationCoordinator))
        self.processor = processor
        self.clock = clock
        self.ids = ids
        self.schedulesInSystem = schedulesInSystem
        self.feedbackStore = feedbackStore
    }

    var body: some View {
        stateContent
            // Reconcile the system authority against saved alarms on launch and every foreground
            // (WG-029), then refresh; `reconcile()` reloads the list when it finishes.
            .task { await model.reconcile() }
            .task { await permission.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.reconcile() }
                    Task { await permission.refresh() }
                }
            }
            .safeAreaInset(edge: .top) {
                if model.isReconciling { ReconcilingBanner() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        Label("Privacy & data", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("privacySettingsButton")
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ReadinessScreen()
                    } label: {
                        Label("Readiness", systemImage: "bed.double")
                    }
                    .accessibilityIdentifier("readinessButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            activeSheet = .describe
                        } label: {
                            Label("Describe your alarm", systemImage: "text.bubble")
                        }
                        .accessibilityIdentifier("describeAlarmButton")
                        Button {
                            activeSheet = .create
                        } label: {
                            Label("Add manually", systemImage: "slider.horizontal.3")
                        }
                        .accessibilityIdentifier("addManualAlarmButton")
                    } label: {
                        Label("Add alarm", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addAlarmButton")
                }
            }
            .sheet(
                item: $activeSheet, onDismiss: { Task { await model.load() } },
                content: { sheet in
                    switch sheet {
                    case .create:
                        CreateAlarmView(processor: processor, clock: clock, ids: ids)
                    case .describe:
                        ConversationalCreateCover(onCreated: { Task { await model.load() } })
                    case .edit(let alarm):
                        CreateAlarmView(
                            editing: alarm, processor: processor, clock: clock, ids: ids,
                            feedbackStore: feedbackStore)
                    }
                }
            )
            .safeAreaInset(edge: .bottom) {
                if schedulesInSystem {
                    AlarmPermissionBanner(model: permission)
                } else {
                    SchedulingDisabledBanner()
                }
            }
            .fullScreenCover(item: $challengeTarget) { target in
                ChallengeTestCover(alarmID: target.id, required: target.requiredSteps)
            }
            .alert(
                "Confirm change", isPresented: confirmationPresented,
                presenting: model.pendingConfirmation
            ) { _ in
                Button("Cancel", role: .cancel) { Task { await model.cancelPendingConfirmation() } }
                Button("Confirm", role: .destructive) { Task { await model.confirmPending() } }
            } message: {
                Text($0.reason)
            }
            .alert("Couldn’t complete", isPresented: actionErrorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.actionError ?? "")
            }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { model.pendingConfirmation != nil },
            // A dismissal that doesn't go through our buttons (e.g. an interruption) must
            // restore true state — symmetric with the error alert below — so the withheld
            // command never lingers pending and re-presents.
            set: { if !$0 { Task { await model.cancelPendingConfirmation() } } })
    }

    private var actionErrorPresented: Binding<Bool> {
        Binding(get: { model.actionError != nil }, set: { if !$0 { model.dismissActionError() } })
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
                message: "Alarms you create will appear here.", identifier: "alarmListEmpty",
                actionTitle: "Add alarm", action: { activeSheet = .create })
        case .loaded(let content):
            AlarmListLoadedView(
                content: content, model: model,
                onEdit: { if let alarm = model.alarm(for: $0) { activeSheet = .edit(alarm) } },
                onTestChallenge: { item in
                    challengeTarget = ChallengeTarget(
                        id: item.id, requiredSteps: item.challengeRequiredSteps ?? 0)
                })
        case .failed(let reason):
            AlarmListMessageView(
                systemImage: "exclamationmark.triangle", title: "Couldn’t load alarms",
                message: reason, identifier: "alarmListError")
        }
    }
}

/// The loaded list: a prominent next-alarm summary section, then every alarm. `List`
/// sections give VoiceOver a logical reading order (summary before the full list). `internal` (not
/// `private`) so the split-out preview file can render it.
struct AlarmListLoadedView: View {
    let content: AlarmListContent
    let model: AlarmListViewModel
    let onEdit: (AlarmID) -> Void
    var onTestChallenge: (AlarmListItem) -> Void = { _ in }

    var body: some View {
        List {
            Section("Next alarm") {
                NextAlarmSummary(item: content.nextAlarm)
            }
            Section("All alarms") {
                ForEach(content.items) { item in
                    AlarmRow(
                        item: item, model: model, onEdit: onEdit,
                        onTestChallenge: onTestChallenge)
                }
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
    let model: AlarmListViewModel
    let onEdit: (AlarmID) -> Void
    /// Present the walk-challenge test for this alarm (only offered when it requires a walk challenge).
    let onTestChallenge: (AlarmListItem) -> Void

    var body: some View {
        HStack {
            Button {
                onEdit(item.id)
            } label: {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.accessibilityLabel)
            .accessibilityHint("Edit alarm")
            .accessibilityIdentifier("alarmRow")

            Toggle("Enabled", isOn: enabledBinding)
                .labelsHidden()
                // The switch trait speaks the on/off value; name the alarm and the
                // consequence so VoiceOver isn't a bare "<label>, switch" with no purpose.
                .accessibilityLabel("\(item.label) alarm")
                .accessibilityHint(item.isEnabled ? "Turns this alarm off" : "Turns this alarm on")
                .accessibilityIdentifier("alarmToggle")
        }
        // `allowsFullSwipe: false`: delete is a deliberate two-step (swipe to reveal, then
        // tap), never a single reflexive full-swipe — so a critical alarm is never destroyed
        // by accident, and its confirmation prompt is always reached by an intentional tap.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await model.delete(item.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            // Speak the consequence, not a bare "Delete" — a VoiceOver user hears whether the
            // alarm will still ring before committing (WG-201/247, #25).
            .accessibilityHint(AlarmVoiceOver.consequence(of: .cancelAlarm))
            .accessibilityIdentifier("deleteAlarm")
        }
        .swipeActions(edge: .leading) {
            // Offered only for a walk-challenge alarm: run the real challenge pipeline now (#18 requires
            // an explicit start). The genuine unattended-ring hookup is device-only (WG-030).
            if item.challengeRequiredSteps != nil {
                Button {
                    onTestChallenge(item)
                } label: {
                    Label("Test challenge", systemImage: "figure.walk")
                }
                .tint(DesignSystem.Colors.accent)
                .accessibilityIdentifier("testChallenge")
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { item.isEnabled },
            set: { enabled in Task { await model.setEnabled(enabled, for: item.id) } })
    }

    @ViewBuilder private var labelStack: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
            Text(item.label).font(DesignSystem.Typography.cardTitle)
            Text(item.nextRingText).font(DesignSystem.Typography.secondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
    }
}
