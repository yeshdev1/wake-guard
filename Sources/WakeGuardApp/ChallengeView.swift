import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// The in-progress wake-challenge screen (WG-071). It keeps the alarm **unmistakably active** until
/// the challenge passes, shows a big, plain progress readout legible during sleep inertia, and — for
/// a user who isn't looking at the screen — **speaks** progress / outcome to VoiceOver and plays a
/// haptic cue on each meaningful change. The accessible non-walking alternative stays pinned and
/// offered until the user is done, so no one is trapped (#21). Pure presentation over
/// `ChallengeViewModel` — it never dismisses the alarm itself.
struct ChallengeView: View {
    let viewModel: ChallengeViewModel
    /// Wired by the app to the accessible-alternative flow (WG-072). **Non-defaulted** so a caller
    /// cannot silently ship a dead-end button — omitting the wiring is a compile error (#21/#22).
    let onUseAccessibleAlternative: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.xl) {
                StatusBadge(style: statusStyle)
                    .accessibilityIdentifier("challengeStatus")

                Text(viewModel.headline)
                    .font(DesignSystem.Typography.screenTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("challengeHeadline")

                VStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView(value: viewModel.progressFraction)
                        .tint(statusTint)
                        .animation(reduceMotion ? nil : .default, value: viewModel.progressFraction)
                    Text(viewModel.progressText)
                        .font(DesignSystem.Typography.screenTitle)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("challengeProgress")
                .accessibilityLabel("Walk progress")
                .accessibilityValue(viewModel.progressText)
                .accessibilityAddTraits(.updatesFrequently)

                if viewModel.machine.phase == .starting || viewModel.machine.phase == .active {
                    keepWalkingDisclaimer
                }

                Text(viewModel.instruction)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: .infinity)
        }
        .background(DesignSystem.Colors.screenBackground)
        .safeAreaInset(edge: .bottom) {
            // Pinned, so the fallback is always reachable even at the largest Dynamic Type.
            if viewModel.offersAccessibleAlternative {
                Button("Can’t walk? Use another way", action: onUseAccessibleAlternative)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("challengeAccessibleAlternative")
                    .padding(DesignSystem.Spacing.lg)
            }
        }
        .accessibilityIdentifier("challengeView")
        .onChange(of: viewModel.lastHapticCue) { _, cue in
            guard let cue else { return }
            playHaptic(cue)
            announce(cue)
        }
    }

    /// A strong, always-on reminder during the walk (WG-305). The step count is reconstructed from the
    /// pedometer's ~1-per-second cumulative delivery, so the on-screen number lags real movement by a
    /// moment — without this, people stop the instant the bar looks full and the walk never verifies.
    private var keepWalkingDisclaimer: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Label("Keep walking!", systemImage: "figure.walk.motion")
                .font(DesignSystem.Typography.sectionTitle)
                .foregroundStyle(statusTint)
            Text("Steps update a moment late — don’t stop early.")
                .font(DesignSystem.Typography.body)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.md)
        .background(
            statusTint.opacity(0.12),
            in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("challengeKeepWalkingDisclaimer")
    }

    private var statusStyle: AlarmStatusStyle {
        AlarmStatusStyle(
            label: viewModel.statusLabel, systemImage: viewModel.statusSystemImage, tint: statusTint
        )
    }

    /// A reinforcing tint only — meaning is carried by the label + icon (never color alone).
    private var statusTint: Color {
        switch viewModel.machine.phase {
        case .active: return DesignSystem.Colors.statusCritical
        case .passed: return DesignSystem.Colors.statusScheduled
        case .timedOut, .failed, .unavailable: return DesignSystem.Colors.statusAttention
        case .idle, .starting: return DesignSystem.Colors.statusOff
        }
    }

    /// Speak the change — a groggy VoiceOver user isn't re-focusing the progress element. A step
    /// crossing a milestone announces just the count (terse, avoids flooding); a pass / not-pass
    /// announces the full status — the most important moment for someone not looking at the screen.
    private func announce(_ cue: ChallengeHapticCue) {
        let message =
            cue == .progressed ? viewModel.progressText : viewModel.accessibilityAnnouncement
        #if canImport(UIKit)
            UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    private func playHaptic(_ cue: ChallengeHapticCue) {
        #if canImport(UIKit)
            switch cue {
            case .progressed:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .passed:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .notPassed:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        #endif
    }
}
