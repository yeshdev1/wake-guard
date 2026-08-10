import SwiftUI

/// The accountless local deletion screen (WG-184). The user can delete individual **optional** data
/// categories (never touches alarms) or perform a **full reset**. The full reset is destructive and is
/// gated behind an explicit confirmation that **spells out the scheduled-alarm consequence**. Design-system,
/// destructive actions are distinct, accessibility-labelled.
struct DataDeletionView: View {
    @Bindable var model: DataDeletionModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("Delete data")
                .font(DesignSystem.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            optionalCategories
            deleteSelectedButton
            Divider()
            fullResetButton
        }
        .padding(DesignSystem.Spacing.lg)
        .confirmationDialog(
            "Delete all data?", isPresented: fullResetBinding, titleVisibility: .visible
        ) {
            Button("Delete everything, including alarms", role: .destructive) {
                Task { await model.confirmFullReset() }
            }
            .accessibilityIdentifier("dataDeletionConfirmFullReset")
            Button("Cancel", role: .cancel) { model.cancelFullReset() }
        } message: {
            Text(
                "This removes all app data and cancels your scheduled alarms. They will not ring. This "
                    + "can’t be undone.")
        }
    }

    private var optionalCategories: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ForEach(OptionalDataCategory.allCases, id: \.self) { category in
                Toggle(isOn: binding(for: category)) {
                    Text(Self.title(for: category))
                }
                .accessibilityIdentifier("dataDeletionToggle_\(category.rawValue)")
            }
        }
    }

    private var deleteSelectedButton: some View {
        Button("Delete selected", role: .destructive) {
            Task { await model.deleteSelectedOptional() }
        }
        .disabled(!model.canDeleteSelected)
        .accessibilityIdentifier("dataDeletionDeleteSelected")
    }

    private var fullResetButton: some View {
        Button("Delete all data", role: .destructive) { model.requestFullReset() }
            .accessibilityIdentifier("dataDeletionRequestFullReset")
    }

    private func binding(for category: OptionalDataCategory) -> Binding<Bool> {
        Binding(
            get: { model.selectedOptional.contains(category) },
            set: { isOn in
                if isOn {
                    model.selectedOptional.insert(category)
                } else {
                    model.selectedOptional.remove(category)
                }
            })
    }

    private var fullResetBinding: Binding<Bool> {
        Binding(get: { model.pendingFullResetConfirmation }, set: { _ in model.cancelFullReset() })
    }

    private static func title(for category: OptionalDataCategory) -> String {
        switch category {
        case .derivedMotion: "Motion history"
        case .recommendations: "Recommendations"
        case .journal: "Sleep journal"
        case .healthDerived: "Health-derived data"
        }
    }
}
