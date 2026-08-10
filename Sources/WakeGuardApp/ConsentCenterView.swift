import SwiftUI

/// The permission & consent center (WG-180). Lists **each** category separately — alarm, notifications,
/// motion, location, health, calendar, cloud AI — with its **current status**, **purpose**, and
/// **revocation guidance**. Design-system only, **no color-only** signals (each status pairs an SF Symbol
/// with a text label), VoiceOver-labelled. Reading this changes nothing; alarms are unaffected.
struct ConsentCenterView: View {
    @Bindable var model: ConsentCenterModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                Text("Permissions & privacy")
                    .font(DesignSystem.Typography.screenTitle)
                    .accessibilityAddTraits(.isHeader)
                ForEach(model.states, id: \.info.category) { state in
                    row(state)
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .task { await model.refresh() }
    }

    @ViewBuilder private func row(_ state: ConsentCategoryState) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text(state.info.title)
                    .font(DesignSystem.Typography.cardTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                statusBadge(state.status)
            }
            Text(state.info.purpose)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
            Label {
                Text(state.info.revocationGuidance)
            } icon: {
                Image(systemName: "arrow.uturn.backward")
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            .accessibilityIdentifier("consentRevocation_\(state.info.category.rawValue)")

            if state.info.isOptional {
                Text("Optional")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("consentRow_\(state.info.category.rawValue)")
    }

    private func statusBadge(_ status: ConsentStatus) -> some View {
        Label {
            Text(Self.label(for: status))
        } icon: {
            Image(systemName: Self.icon(for: status))
        }
        .font(DesignSystem.Typography.statusLabel)
        .accessibilityIdentifier("consentStatus")
    }

    private static func label(for status: ConsentStatus) -> String {
        switch status {
        case .granted: "On"
        case .denied: "Off"
        case .notDetermined: "Not set"
        case .restricted: "Restricted"
        case .unavailable: "Unavailable"
        }
    }

    private static func icon(for status: ConsentStatus) -> String {
        switch status {
        case .granted: "checkmark.circle"
        case .denied: "slash.circle"
        case .notDetermined: "questionmark.circle"
        case .restricted: "lock.circle"
        case .unavailable: "minus.circle"
        }
    }
}
