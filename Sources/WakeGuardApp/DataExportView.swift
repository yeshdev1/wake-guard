import SwiftUI

/// The local-data export screen (WG-183). The user explicitly taps **Prepare export**; the resulting
/// versioned JSON is offered through the **system share sheet** (`ShareLink`), so the OS and the user
/// decide where it goes — WakeGuard never sends it anywhere. Design-system, accessibility-labelled.
struct DataExportView: View {
    @Bindable var model: DataExportModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("Export your data")
                .font(DesignSystem.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            Text(
                "Creates a file with your alarms, settings, and history. It stays on your device until you "
                    + "choose where to share it."
            )
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.secondaryText)

            Button("Prepare export") { Task { await model.prepareExport() } }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("dataExportPrepare")

            if let url = model.fileURL {
                ShareLink(item: url) {
                    Label("Share export", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("dataExportShare")
            }

            if model.didFail {
                Label {
                    Text("We couldn’t prepare the export. Please try again.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("dataExportError")
            }
        }
        .padding(DesignSystem.Spacing.lg)
    }
}
