import SwiftUI

/// The Settings "On-device intelligence" section (WG-162). Surfaces whether AI suggestions are available,
/// with an honest per-state explanation, and **always** states that alarms are unaffected. Design-system
/// only; **no color-only** signal (the state pairs an SF Symbol with text); VoiceOver-labelled with stable
/// identifiers. Nothing here schedules or cancels an alarm — it only reflects advisory-feature
/// availability.
struct AIAvailabilitySection: View {
    @Bindable var model: AIAvailabilityModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("On-device intelligence")
                .font(DesignSystem.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            if let status = model.status {
                content(status)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .task { model.refresh() }
    }

    @ViewBuilder private func content(_ status: AIAvailabilityStatusCopy) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label {
                Text(status.title).font(DesignSystem.Typography.body)
            } icon: {
                Image(systemName: status.isAvailable ? "sparkles" : "info.circle")
            }
            .accessibilityIdentifier("aiAvailabilityTitle")

            Text(status.detail)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("aiAvailabilityDetail")

            Label {
                Text(status.alarmsReassurance).font(DesignSystem.Typography.caption)
            } icon: {
                Image(systemName: "alarm")
            }
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            .accessibilityIdentifier("aiAvailabilityAlarmsReassurance")
        }
        .accessibilityElement(children: .combine)
    }
}
