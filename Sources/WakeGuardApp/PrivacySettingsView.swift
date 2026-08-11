import SwiftUI

/// The Privacy & data entry point (WG-250 composition). The single screen that routes to the permission &
/// consent center (WG-180), the local-data export (WG-183), and accountless deletion (WG-184) — the controls
/// the privacy policy promises. It reads its models from the composed `\.appEnvironment` and renders a safe
/// state if the environment is missing. Holds no alarm authority — nothing here changes whether an alarm
/// rings (#9).
struct PrivacySettingsView: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        if let environment {
            PrivacySettingsScreen(environment: environment)
        } else {
            ContentUnavailableView("Privacy settings unavailable", systemImage: "hand.raised")
                .accessibilityIdentifier("privacySettingsUnavailable")
        }
    }
}

/// Owns the three privacy models in `@State` (built once from the environment) so pushed screens keep their
/// state across re-renders — the same pattern as `AlarmListScreen`.
private struct PrivacySettingsScreen: View {
    @State private var consent: ConsentCenterModel
    @State private var export: DataExportModel
    @State private var deletion: DataDeletionModel
    @State private var diagnostics: DiagnosticsModel
    @State private var diagnosticsShareURL: IdentifiableURL?

    init(environment: AppEnvironment) {
        _consent = State(
            wrappedValue: ConsentCenterModel(provider: environment.consentStatusProvider))
        _export = State(
            wrappedValue: DataExportModel(
                clock: environment.clock,
                categories: { await environment.exportData.categories() }))
        _deletion = State(
            wrappedValue: DataDeletionModel(coordinator: environment.deletionCoordinator))
        _diagnostics = State(
            wrappedValue: DiagnosticsModel(provider: environment.diagnosticsProvider))
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ConsentCenterView(model: consent)
                } label: {
                    Label("Permissions & privacy", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("privacyLinkConsent")

                NavigationLink {
                    DataExportView(model: export)
                } label: {
                    Label("Export your data", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("privacyLinkExport")

                NavigationLink {
                    DataDeletionView(model: deletion)
                } label: {
                    Label("Delete your data", systemImage: "trash")
                }
                .accessibilityIdentifier("privacyLinkDelete")

                NavigationLink {
                    DiagnosticsView(
                        model: diagnostics,
                        onExport: { diagnosticsShareURL = IdentifiableURL(url: $0) })
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
                .accessibilityIdentifier("privacyLinkDiagnostics")
            } footer: {
                Text(
                    "Your data stays on this device. Exporting or deleting never sends it anywhere."
                )
            }
        }
        .navigationTitle("Privacy & data")
        .sheet(item: $diagnosticsShareURL) { item in
            // The user explicitly confirms sharing the redacted diagnostics report via the system sheet.
            ShareLink(item: item.url) {
                Label("Share diagnostics report", systemImage: "square.and.arrow.up")
            }
            .padding()
        }
    }
}

/// A share URL wrapped so it can drive a `.sheet(item:)` presentation.
private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

#Preview("Privacy settings") {
    NavigationStack { PrivacySettingsView().environment(\.appEnvironment, .preview) }
}
