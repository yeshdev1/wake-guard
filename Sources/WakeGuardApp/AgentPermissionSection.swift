import SwiftUI

/// The Settings "Agent autonomy" section (WG-171). Lets the user choose how much the advisory agent may
/// do — **recommend only** or **ask before acting** — and states plainly that **critical alarms always
/// require confirmation** and that **automatic adjustment isn't available**. Design-system only, no
/// color-only signals, VoiceOver-labelled. Changing this never affects whether an alarm rings.
struct AgentPermissionSection: View {
    @Bindable var model: AgentPermissionModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Agent autonomy")
                .font(DesignSystem.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            Picker("Agent autonomy", selection: modeBinding) {
                ForEach(model.selectableModes, id: \.self) { mode in
                    Text(Self.title(for: mode)).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .accessibilityIdentifier("agentPermissionPicker")

            Text(Self.detail(for: model.mode))
                .font(DesignSystem.Typography.secondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("agentPermissionDetail")

            note(
                "Critical alarms always ask for confirmation before any change.",
                icon: "exclamationmark.shield", identifier: "agentPermissionCriticalNote")
            note(
                "Automatic adjustment isn’t available — the agent only suggests or asks.",
                icon: "hand.raised", identifier: "agentPermissionAutoNote")

            if model.saveDidFail {
                note(
                    "We couldn’t save that change. Please try again.",
                    icon: "exclamationmark.triangle", identifier: "agentPermissionSaveError")
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .task { await model.load() }
    }

    private var modeBinding: Binding<AgentPermissionMode> {
        Binding(
            get: { model.mode },
            set: { newMode in Task { await model.setMode(newMode) } })
    }

    private func note(_ text: String, icon: String, identifier: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
        }
        .font(DesignSystem.Typography.caption)
        .foregroundStyle(DesignSystem.Colors.secondaryText)
        .accessibilityIdentifier(identifier)
    }

    private static func title(for mode: AgentPermissionMode) -> String {
        switch mode {
        case .recommendOnly: "Recommend only"
        case .askBeforeActing: "Ask before acting"
        case .autoAdjust: "Automatic"
        }
    }

    private static func detail(for mode: AgentPermissionMode) -> String {
        switch mode {
        case .recommendOnly: "The agent suggests changes; you apply them yourself."
        case .askBeforeActing: "The agent proposes a change and asks before it’s applied."
        case .autoAdjust: "Not available."
        }
    }
}
