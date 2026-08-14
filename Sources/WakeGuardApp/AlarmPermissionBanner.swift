import SwiftUI

/// The alarm-authorization affordance on the alarm list, shown when the build schedules real system
/// alarms but authorization is not yet granted (WG-025 / runs-on-a-phone step 2). Renders **nothing**
/// when authorized (or not yet resolved) — a ringing, authorized app shows no banner. The system
/// dialog is always preceded by the explanation sheet (never an unexplained prompt). Read-only with
/// respect to alarms: a denial never drops an alarm (#10), it only asks the user to grant or retry.
struct AlarmPermissionBanner: View {
    let model: AlarmPermissionModel
    @State private var showingExplanation = false

    /// One banner action button's presentation + behavior — bundled so `banner(...)` stays within the
    /// parameter budget and each action carries its own VoiceOver hint describing the consequence.
    private struct ButtonSpec {
        let title: String
        let hint: String
        let identifier: String
        let action: () -> Void
    }

    var body: some View {
        content
            .sheet(isPresented: $showingExplanation) {
                AlarmPermissionExplanation(
                    onContinue: {
                        showingExplanation = false
                        Task { await model.requestAfterExplanation() }
                    },
                    onCancel: { showingExplanation = false })
            }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .none, .authorized:
            EmptyView()
        case .explainThenRequest:
            banner(
                icon: "bell.badge",
                message: "Turn on alarms so they can ring at the times you set.",
                button: ButtonSpec(
                    title: "Turn on", hint: "Explains, then turns on alarms",
                    identifier: "permissionEnable", action: { showingExplanation = true }))
        case .deniedOpenSettings:
            banner(
                icon: "bell.slash",
                message: "Alarms need permission to ring. Your alarms are saved.",
                button: ButtonSpec(
                    title: "Open Settings", hint: "Opens Settings to allow alarms",
                    identifier: "permissionOpenSettings",
                    action: { Task { await model.openSettings() } }))
        case .unknownKeepSafe:
            banner(
                icon: "exclamationmark.triangle",
                message: "We couldn’t turn on alarms. Your alarms are still saved.",
                button: ButtonSpec(
                    title: "Try again", hint: "Tries turning on alarms again",
                    identifier: "permissionRetry", action: { showingExplanation = true }))
        case .restrictedUseFallback:
            banner(
                icon: "lock",
                message: "System alarms are restricted on this device. Existing alarms are kept.",
                button: nil)
        }
    }

    private func banner(icon: String, message: String, button: ButtonSpec?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                label(icon, message)
                Spacer(minLength: DesignSystem.Spacing.sm)
                actionButton(button)
            }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                label(icon, message)
                actionButton(button)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.Colors.statusAttention.opacity(0.15))
        // `.contain` (not `.combine`) so the message reads as one element AND the button stays
        // independently actionable; the message stack supplies its own combined label below.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alarmPermissionBanner")
    }

    private func label(_ icon: String, _ message: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(message).font(DesignSystem.Typography.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    @ViewBuilder private func actionButton(_ spec: ButtonSpec?) -> some View {
        if let spec {
            // No font shrink: `.borderedProminent` at `.small` keeps the minimum hit target and the
            // filled-label contrast guarantee (a footnote override undercut both).
            Button(spec.title, action: spec.action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier(spec.identifier)
                .accessibilityHint(spec.hint)
        }
    }
}

/// The permission explanation shown *before* the system dialog (WG-025 acceptance: the prompt is
/// never unexplained). Scrollable so it stays legible at the largest Dynamic Type; the two actions
/// are semantic toolbar buttons for VoiceOver.
private struct AlarmPermissionExplanation: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text("Let your alarms ring").font(DesignSystem.Typography.sectionTitle)
                    Text(
                        "Alarm Agent uses your device’s system alarms so your wake-up and critical "
                            + "alarms reliably ring — through silent mode and Focus — at the times you "
                            + "set. You can change or turn this off anytime in Settings."
                    )
                    .font(DesignSystem.Typography.body)
                    Text("Next, iOS will ask your permission to schedule alarms.")
                        .font(DesignSystem.Typography.secondary)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Alarm permission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now", action: onCancel)
                        .accessibilityIdentifier("permissionExplanationCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: onContinue)
                        .accessibilityIdentifier("permissionExplanationContinue")
                }
            }
        }
        .accessibilityIdentifier("alarmPermissionExplanation")
    }
}
