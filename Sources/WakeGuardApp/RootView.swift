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
    @State private var needsOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var deepLink = deepLink
        AlarmListView()
            .task {
                await setUpPreAlarmNotifications()
                await runRetentionCleanup()
                startTimeZoneMonitoring()
                await loadOnboardingState()
            }
            .fullScreenCover(isPresented: $needsOnboarding) {
                OnboardingView(
                    model: onboarding, onFinished: { Task { await completeOnboarding() } })
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await runPreAlarmWork() } }
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
        guard let environment, environment.schedulesAlarmsInSystem else { return }
        let settings = (try? await environment.settingsRepository.settings()) ?? .default
        needsOnboarding = !settings.hasCompletedOnboarding
    }

    /// Persist that onboarding is done, so it doesn't show again, then dismiss it. Best-effort — a failed
    /// save just means the intro shows once more, never a broken launch.
    @MainActor
    private func completeOnboarding() async {
        needsOnboarding = false
        guard let environment else { return }
        var settings = (try? await environment.settingsRepository.settings()) ?? .default
        settings.hasCompletedOnboarding = true
        try? await environment.settingsRepository.save(settings)
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
            Text("WakeGuard can’t start")
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
