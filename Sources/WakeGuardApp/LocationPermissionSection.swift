import SwiftUI

/// The optional significant-location education + control (WG-109). Explains the approximate purpose and
/// battery behavior, makes explicit that the feature works without permission, and lets the user turn
/// monitoring on or **off**. Design-system only; **no color-only** signals (every note pairs an SF Symbol
/// with text); VoiceOver-labelled with stable identifiers. Toggling never affects whether an alarm rings
/// (#9) — it only sets the optional `locationContextEnabled` control.
struct LocationPermissionSection: View {
    @Bindable var model: LocationMonitoringModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Location (optional)")
                .font(DesignSystem.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            education

            Toggle(isOn: monitoringBinding) {
                Text("Use approximate location")
                    .font(DesignSystem.Typography.body)
            }
            .accessibilityIdentifier("locationMonitoringToggle")
            .accessibilityHint("Turns significant-location travel corroboration on or off")

            if model.saveDidFail {
                note(
                    "We couldn’t save that change. Please try again.",
                    icon: "exclamationmark.triangle", identifier: "locationSaveError")
            }
            permissionOffNote
        }
        .padding(DesignSystem.Spacing.lg)
        .task { await model.refresh() }
    }

    private var education: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(model.education.purpose)
            Text(model.education.batteryBehavior)
            Text(model.education.worksWithoutPermission)
        }
        .font(DesignSystem.Typography.body)
        .foregroundStyle(DesignSystem.Colors.secondaryText)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("locationEducation")
    }

    private var monitoringBinding: Binding<Bool> {
        Binding(
            get: { model.isMonitoringEnabled },
            set: { enabled in Task { await model.setMonitoringEnabled(enabled) } })
    }

    /// Shown only when the user enabled monitoring but the OS permission can't monitor — reassures that
    /// the app still works (time-zone detection + alarms). Never a color-only signal.
    @ViewBuilder private var permissionOffNote: some View {
        if let status = model.authorizationStatus, !status.canMonitor, model.isMonitoringEnabled {
            note(
                "Location access is off in Settings. Your alarms and time-zone detection still work.",
                icon: "info.circle", identifier: "locationPermissionOffNote")
        }
    }

    private func note(_ message: String, icon: String, identifier: String) -> some View {
        Label(message, systemImage: icon)
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            .accessibilityIdentifier(identifier)
    }
}
