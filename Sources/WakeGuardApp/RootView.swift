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

    var body: some View {
        @Bindable var deepLink = deepLink
        AlarmListView()
            .task { await setUpPreAlarmNotifications() }
            .onOpenURL { url in
                let route = DeepLinkParser.route(for: url)
                Task { await deepLink.open(route, using: environment) }
            }
            .sheet(item: $deepLink.alarmToEdit) { alarm in
                if let environment {
                    CreateAlarmView(
                        editing: alarm, processor: environment.alarmCommandProcessor,
                        clock: environment.clock, ids: environment.identifierGenerator)
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
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text("WakeGuard can’t start")
                .font(.title.bold())
            Text(
                "Local storage is unavailable, so your alarms could not be loaded. "
                    + "Please make sure your device is unlocked, then restart the app."
            )
            .font(.footnote)
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
