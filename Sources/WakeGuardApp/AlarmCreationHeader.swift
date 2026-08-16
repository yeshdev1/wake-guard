import SwiftUI

/// The alarm-creation header at the top of the list (WG-300/302): a tappable **"Describe your alarm"** card
/// that opens the conversational flow, and an **"Add manually"** button that opens the editor. When
/// on-device intelligence isn't available it shows an honest, non-blocking, **reason-aware** hint — "turn it
/// on" (with "Open Settings") if it's merely off, or "this iPhone doesn't support it, add manually" if it's
/// ineligible/preparing — always pointing to manual entry so no one is stuck. Design-system only; no
/// color-only signal; VoiceOver-labelled.
struct AlarmCreationHeader: View {
    let onDescribe: () -> Void
    let onManual: () -> Void
    @Bindable var availability: AIAvailabilityModel
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            describeCard
            if let hint = AlarmCreationHint.hint(for: availability.decision) {
                hintView(hint)
            }
            Button("Add manually", systemImage: "slider.horizontal.3", action: onManual)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("addManualAlarmButton")
        }
        .task { availability.refresh() }
    }

    private var describeCard: some View {
        Button(action: onDescribe) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "text.bubble")
                    .font(DesignSystem.Typography.sectionTitle)
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text("Describe your alarm")
                        .font(DesignSystem.Typography.cardTitle)
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                    Text("e.g. “wake me at 7 tomorrow and make it critical”")
                        .font(DesignSystem.Typography.secondary)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.md)
            .background(
                DesignSystem.Colors.surface,
                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("describeAlarmButton")
        .accessibilityHint("Opens a guided flow to create an alarm from a description")
    }

    private func hintView(_ hint: AlarmCreationHint) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Label {
                Text(hint.message)
            } icon: {
                Image(systemName: "sparkles")
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            if hint.showsOpenSettings {
                Button("Open Settings", action: onOpenSettings)
                    .font(DesignSystem.Typography.caption)
                    .accessibilityIdentifier("openAISettingsButton")
            }
        }
        .accessibilityIdentifier("aiCreationHint")
    }
}
