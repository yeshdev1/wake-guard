import SwiftUI

/// Placeholder root view for the app shell (WG-003 scaffold).
///
/// Real alarm UI arrives in epoch E03. Kept intentionally free of logic so the
/// composition root stays thin.
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

#Preview {
    RootView()
}
