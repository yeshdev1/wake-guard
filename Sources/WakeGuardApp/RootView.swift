import SwiftUI
import UserNotifications

/// The app's root view. Hosts the alarm list (WG-041), which reads its ports from the
/// composed `\.appEnvironment` injected above it (WG-018) and renders an explicit safe
/// state if the environment is missing. Handles incoming deep links (WG-049): a link only
/// ever *opens a screen* (or shows a safe error) — it never mutates an alarm on its own.
struct RootView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var deepLink = DeepLinkModel()
    @State private var notificationDelegate: PreAlarmNotificationDelegate?
    @State private var onboarding = OnboardingModel()
    @State private var onboardingResolved = false
    @State private var needsOnboarding = false
    @State private var challengeInbox = WakeChallengeLaunchInbox.shared
    @State private var challengeTarget: ChallengeTarget?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Onboarding **replaces** the list until it's done, so the list's launch work (reconcile,
        // permission reads, notification setup) never runs behind the intro — no permission prompt
        // precedes onboarding. While the persisted flag is being read, show a brief placeholder.
        Group {
            if !onboardingResolved {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("launchResolving")
            } else if needsOnboarding {
                OnboardingView(
                    model: onboarding, onFinished: { Task { await completeOnboarding() } })
            } else {
                mainList
            }
        }
        .task { await loadOnboardingState() }
    }

    @ViewBuilder private var mainList: some View {
        @Bindable var deepLink = deepLink
        AlarmListView()
            .task { await startLifecycle() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await runPreAlarmWork() }
                    Task { await presentChallengeIfRequested(challengeInbox.requestedAlarmID) }
                }
            }
            .onChange(of: challengeInbox.requestedAlarmID) { _, id in
                Task { await presentChallengeIfRequested(id) }
            }
            .fullScreenCover(item: $challengeTarget) { target in
                ChallengeTestCover(alarmID: target.id, required: target.requiredSteps)
            }
            .onOpenURL { url in
                let route = DeepLinkParser.route(for: url)
                Task { await deepLink.open(route, using: environment) }
            }
            .sheet(item: $deepLink.alarmToEdit) { alarm in
                if let environment {
                    CreateAlarmView(
                        editing: alarm, processor: environment.alarmCommandProcessor,
                        clock: environment.clock, ids: environment.identifierGenerator,
                        feedbackStore: environment.preAlarmFeedback)
                }
            }
            .alert(
                "Couldn’t open link", isPresented: deepLinkErrorPresented,
                presenting: deepLink.errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    /// The list's launch work — runs only once the list is shown (post-onboarding, or immediately for an
    /// already-onboarded user), so any permission prompt appears after the intro, never before it.
    @MainActor
    private func startLifecycle() async {
        await setUpPreAlarmNotifications()
        await runRetentionCleanup()
        startTimeZoneMonitoring()
    }

    /// Register the pre-alarm prompt category + install the notification delegate on launch — only in
    /// the production graph (`schedulesAlarmsInSystem`), so previews / UI tests never touch
    /// `UserNotifications`. Installed once; the delegate routes a tapped prompt action to the processor
    /// (runs-on-a-phone step 5). `UNUserNotificationCenter` holds the delegate weakly, so `@State`
    /// retains it for the app's lifetime.
    @MainActor
    private func setUpPreAlarmNotifications() async {
        guard let environment, environment.schedulesAlarmsInSystem, notificationDelegate == nil
        else { return }
        let delegate = PreAlarmNotificationDelegate(
            responder: environment.preAlarmResponder, now: { environment.clock.now })
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        await environment.preAlarmNotifications.registerPromptCategory()
        await environment.preAlarmNotifications.requestAuthorization()
        // Foreground fallback (WG-089 / step 6): evaluate upcoming alarms now, so a prompt can surface
        // when the app is open near an alarm even if no background opportunity ran.
        await environment.preAlarmWork.run(now: environment.clock.now)
    }

    /// Show first-launch onboarding once — production only (WG-200), so previews / UI tests go straight to
    /// the list. Reads the persisted flag; a fresh install (or a failed read → default) shows the intro.
    @MainActor
    private func loadOnboardingState() async {
        guard !onboardingResolved else { return }
        // Always resolve, so the list eventually shows. Non-production graphs (previews / UI tests) skip
        // onboarding entirely and go straight to the list.
        defer { onboardingResolved = true }
        guard let environment, environment.schedulesAlarmsInSystem else {
            needsOnboarding = false
            return
        }
        let settings = (try? await environment.settingsRepository.settings()) ?? .default
        needsOnboarding = !settings.hasCompletedOnboarding
    }

    /// Persist that onboarding is done, so it doesn't show again, then dismiss it. Best-effort — a failed
    /// save just means the intro shows once more, never a broken launch.
    @MainActor
    private func completeOnboarding() async {
        // Persist first, then switch to the list — its `startLifecycle` requests the notification
        // permission in context, after the intro rather than before it.
        if let environment {
            var settings = (try? await environment.settingsRepository.settings()) ?? .default
            settings.hasCompletedOnboarding = true
            try? await environment.settingsRepository.save(settings)
        }
        needsOnboarding = false
    }

    /// Prune local data past its retention window on launch — production only, opportunistic + best-effort
    /// (#9), bounded by the 365-day critical-audit floor (WG-250/182). Never touches an alarm.
    @MainActor
    private func runRetentionCleanup() async {
        guard let environment, environment.schedulesAlarmsInSystem else { return }
        await environment.retentionCleanup.run()
    }

    /// Start the device time-zone monitor at launch — production only (WG-100). It reconciles alarms in the
    /// new zone when the system zone changes, so a background zone change is corrected live rather than
    /// only on the next foreground. `start()` is idempotent; the monitor lives in the environment.
    @MainActor
    private func startTimeZoneMonitoring() {
        guard let environment, environment.schedulesAlarmsInSystem else { return }
        environment.timeZoneMonitor.start()
    }

    /// Re-run the pre-alarm evaluation on every foreground (production only) — advisory, de-duped, and
    /// holds no alarm authority (#7/#8/#9), so it never affects whether an alarm rings.
    @MainActor
    private func runPreAlarmWork() async {
        guard let environment, environment.schedulesAlarmsInSystem else { return }
        await environment.preAlarmWork.run(now: environment.clock.now)
    }

    /// Present the walk challenge for an alarm requested by its "Start walk" system-alarm button (WG-282) —
    /// navigational only, never a mutation. Looks up the alarm's required steps; a missing alarm falls back
    /// to 0 and the runtime still offers the accessible alternative, so no one is trapped (#21/#22).
    ///
    /// **Consume-on-present (WG-295):** the request is cleared the moment the cover is presented — never on
    /// `onDisappear`. Otherwise a post-pass scenePhase flap (the AlarmKit overlay vanishing as the ring
    /// stops) re-read the still-set inbox and re-presented a zombie challenge at 0 steps after dismissal.
    /// Idempotent: a repeat request for the alarm already on screen is a no-op, so an intent re-fire or
    /// scene flap can never tear down a live run.
    @MainActor
    private func presentChallengeIfRequested(_ id: UUID?) async {
        guard let id, let environment else { return }
        let alarmID = AlarmID(id)
        guard challengeTarget?.id != alarmID else {
            challengeInbox.clear()
            return
        }
        let steps = (try? await environment.alarmRepository.alarm(id: alarmID))?
            .challengePolicy.requiredSteps
        // Re-check after the await: the request may have been consumed or the cover presented meanwhile.
        guard challengeInbox.requestedAlarmID == id, challengeTarget?.id != alarmID else { return }
        challengeTarget = ChallengeTarget(id: alarmID, requiredSteps: steps ?? 0)
        challengeInbox.clear()
    }

    private var deepLinkErrorPresented: Binding<Bool> {
        Binding(
            get: { deepLink.errorMessage != nil },
            set: { if !$0 { deepLink.errorMessage = nil } })
    }
}

/// Shown when the composition root cannot build the production dependency graph —
/// e.g. Core Data storage is unavailable. Honest about what failed and that alarms
/// are not loaded, without claiming a safety it cannot guarantee (CLAUDE.md error
/// rules).
struct CompositionErrorView: View {
    let error: Error

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(DesignSystem.Typography.screenTitle)
                .accessibilityHidden(true)
            Text("Alarm Agent can’t start")
                .font(DesignSystem.Typography.sectionTitle)
            Text(
                "Local storage is unavailable, so your alarms could not be loaded. "
                    + "Please make sure your device is unlocked, then restart the app."
            )
            .font(DesignSystem.Typography.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityIdentifier("compositionError")
    }
}

#Preview("Root") {
    // Previews use the fake (in-memory) graph — nothing touches disk (WG-018).
    RootView().environment(\.appEnvironment, .preview)
}

#Preview("Composition error") {
    CompositionErrorView(error: PersistenceError.noStoreDescription)
}
