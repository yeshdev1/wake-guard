import SwiftUI

/// The app's root view. Hosts the alarm list (WG-041), which reads its ports from the
/// composed `\.appEnvironment` injected above it (WG-018) and renders an explicit safe
/// state if the environment is missing.
struct RootView: View {
    var body: some View {
        AlarmListView()
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
