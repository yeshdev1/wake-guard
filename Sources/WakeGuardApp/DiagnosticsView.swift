import SwiftUI

/// The operational diagnostics screen (WG-230). Shows **permission status**, **reconciliation state**, the
/// **last safe schedule sync**, and **redacted errors** — all coarse, with **no sensitive raw data**. The
/// diagnostics can be **exported by an explicit user action** via the system share sheet. Design-system,
/// accessibility-labelled.
struct DiagnosticsView: View {
    @Bindable var model: DiagnosticsModel
    /// Presents the export share sheet with the given URL — wired by the parent.
    var onExport: (URL) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Diagnostics")
                    .font(DesignSystem.Typography.screenTitle)
                    .accessibilityAddTraits(.isHeader)

                if let report = model.report {
                    Text(report)
                        .font(DesignSystem.Typography.body.monospaced())
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                        .accessibilityIdentifier("diagnosticsReport")
                }

                Button("Export diagnostics") {
                    if let export = model.exportReport(),
                        let url = try? export.writeToTemporaryFile()
                    {
                        onExport(url)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("diagnosticsExport")
                .accessibilityHint("Shares a redacted diagnostics report")
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .task { await model.refresh() }
    }
}
