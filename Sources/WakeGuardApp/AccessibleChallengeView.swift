import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// The accessible (non-walking) alternative screen (WG-072) — presented when a user who can't walk
/// (or whose sensors failed) chooses "another way". Non-stigmatizing, affirming copy (SCOPE §2.3 /
/// #22); a deliberate tap sequence or press-and-hold completes the same challenge. It is itself
/// accessible: a big live count, per-tap VoiceOver speech, and — because a sustained long-press is a
/// VoiceOver / motor dead-end — an assistive-tech activation that completes the hold, so the fallback
/// is never a dead-end (#21). Pure presentation; the machine advances only on this user input, and
/// there is no AI path to it (#1).
struct AccessibleChallengeView: View {
    let viewModel: AccessibleChallengeViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Text(viewModel.title)
                .font(DesignSystem.Typography.screenTitle)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("accessibleChallengeTitle")

            Text(viewModel.instruction)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .multilineTextAlignment(.center)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(viewModel.progressText)
                    .font(DesignSystem.Typography.screenTitle)
                    .monospacedDigit()
                    .accessibilityIdentifier("accessibleChallengeProgressText")
                progressBar
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progress")
            .accessibilityValue(viewModel.progressText)
            .accessibilityAddTraits(.updatesFrequently)

            Spacer()

            control
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.screenBackground)
        .accessibilityIdentifier("accessibleChallengeView")
        .onChange(of: viewModel.isPassed) { _, passed in
            if passed { announce(viewModel.passedAnnouncement, priority: .high) }
        }
    }

    @ViewBuilder private var control: some View {
        switch viewModel.kind {
        case .tapSequence:
            Button("Tap to turn off the alarm") {
                if viewModel.tap() { announce(viewModel.progressText) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("accessibleChallengeTap")
        case .pressAndHold:
            Text("Press and hold")
                .font(DesignSystem.Typography.controlLabel)
                .foregroundStyle(DesignSystem.Colors.onFilled)
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.lg)
                .background(
                    DesignSystem.Colors.accent,
                    in: RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
                )
                .contentShape(Rectangle())
                .accessibilityIdentifier("accessibleChallengeHold")
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Turn off the alarm")
                .accessibilityHint("Press and hold, or double-tap to turn off the alarm")
                // Assistive tech (VoiceOver / Switch Control) can't do a sustained press — an
                // activation completes the same challenge, so the hold is never a dead-end (#21).
                .accessibilityAction { viewModel.completeAccessibly() }
                .onLongPressGesture(
                    minimumDuration: viewModel.machine.requirements.holdDuration,
                    maximumDistance: 40
                ) {
                    viewModel.holdTick()
                } onPressingChanged: { pressing in
                    if pressing { viewModel.beginHold() } else { viewModel.endHold() }
                }
        }
    }

    @ViewBuilder private var progressBar: some View {
        if viewModel.kind == .pressAndHold {
            // A timeline so the bar fills live while held; paused when not actively holding. Under Reduce
            // Motion, throttle to coarse ~0.5s steps instead of per-frame growth (WG-247) — the bar still
            // updates (functional feedback #22), but it steps rather than continuously animating.
            TimelineView(
                .animation(
                    minimumInterval: reduceMotion ? 0.5 : nil,
                    paused: !viewModel.isHoldInProgress)
            ) { _ in bar }
        } else {
            bar
        }
    }

    private var bar: some View {
        ProgressView(value: viewModel.progressFraction)
            .tint(DesignSystem.Colors.accent)
            .animation(reduceMotion ? nil : .default, value: viewModel.progressFraction)
            .accessibilityIdentifier("accessibleChallengeProgress")
    }

    private func announce(_ message: String, priority: UIAccessibilityPriority = .default) {
        #if canImport(UIKit)
            let announcement = NSAttributedString(
                string: message, attributes: [.accessibilitySpeechAnnouncementPriority: priority])
            UIAccessibility.post(notification: .announcement, argument: announcement)
        #endif
    }
}
