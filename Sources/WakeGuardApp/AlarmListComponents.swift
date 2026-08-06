import SwiftUI

/// A non-blocking banner shown while reconciliation runs (WG-029) — the alarm list stays
/// visible beneath it, so the user always sees their known alarms.
struct ReconcilingBanner: View {
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ProgressView().controlSize(.small)
            Text("Checking your alarms…").font(DesignSystem.Typography.secondary)
            Spacer()
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.Colors.surface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking your alarms")
        .accessibilityIdentifier("reconcilingBanner")
    }
}

/// A persistent disclosure shown while system scheduling is not yet wired (the WG-042
/// interim `DeferredAlarmManagerAdapter`): alarms are saved but will not ring until the
/// AlarmKit integration lands, so a saved alarm is never silently implied to ring (CLAUDE.md
/// "state explicitly whether the alarm is safe"). Icon + text — not conveyed by color alone.
struct SchedulingDisabledBanner: View {
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "bell.slash").accessibilityHidden(true)
            Text("Alarms are saved but won’t ring yet on this device.")
                .font(DesignSystem.Typography.caption)
            Spacer()
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.Colors.statusAttention.opacity(0.15))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Alarms are saved but won’t ring yet on this device.")
        .accessibilityIdentifier("schedulingDisabledBanner")
    }
}

/// A centered message state (loading / empty / error / unavailable). The message is one
/// combined accessibility element with a stable identifier; an optional action button stays
/// separately focusable (so an empty state isn't a VoiceOver dead-end).
struct AlarmListMessageView: View {
    var progress = false
    var systemImage: String?
    let title: String
    let message: String
    let identifier: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            VStack(spacing: DesignSystem.Spacing.md) {
                if progress {
                    ProgressView()
                } else if let systemImage {
                    Image(systemName: systemImage).font(.largeTitle)
                        .foregroundStyle(DesignSystem.Colors.secondaryText).accessibilityHidden(
                            true)
                }
                Text(title).font(DesignSystem.Typography.sectionTitle)
                if !message.isEmpty {
                    Text(message).font(DesignSystem.Typography.secondary)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("\(identifier)Action")
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
