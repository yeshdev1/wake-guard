import SwiftUI

/// Application entry point and composition root.
///
/// Per ADR-003 and the WG-003 acceptance criteria, this type holds **no
/// business logic**. Feature wiring — repositories, the policy engine, the
/// scheduling engine, sensor adapters — is composed here in later tasks. Today
/// it only presents the root view.
@main
struct WakeGuardApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
