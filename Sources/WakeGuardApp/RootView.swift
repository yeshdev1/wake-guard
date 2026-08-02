import SwiftUI

/// Placeholder root view for the app shell (WG-003 scaffold).
///
/// Real alarm UI arrives in epoch E03. Kept intentionally free of logic so the
/// composition root stays thin. It reads no dependencies yet; the composed
/// `\.appEnvironment` is injected above it (WG-018) for the screens that will.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "alarm")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text("WakeGuard")
                .font(.title.bold())
            Text("Project scaffold — alarm features arrive in later tasks.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityIdentifier("rootScaffold")
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
