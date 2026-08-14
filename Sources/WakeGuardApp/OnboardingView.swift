import SwiftUI

/// The progressive onboarding screen (WG-200). It gathers **only alarm essentials** (notifications +
/// alarms), then offers an optional first alarm the user can **skip** and still reach a usable app. Optional
/// data permissions (motion, location, health, calendar, cloud AI) are **not** requested here — they are
/// asked for later, in context. Design-system, accessibility-labelled.
///
/// Layout: the step **title is the hero** — centred in the middle of the screen, italic — with the body copy
/// and controls as its subcontent directly beneath. The whole group **fades in** on appear (a pure opacity
/// cross-fade; removed under Reduce Motion, WG-203).
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer(minLength: 0)
            hero
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .opacity(revealed ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: revealed)
        .onAppear { revealed = true }
        .onChange(of: model.isComplete) { _, complete in
            if complete { onFinished() }
        }
    }

    /// The centred hero: the italic title, its subtitle, and the controls — one group in the vertical
    /// middle, everything subordinate to the title.
    @ViewBuilder private var hero: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(Self.title(for: model.step))
                    .font(DesignSystem.Typography.screenTitle)
                    .italic()
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(Self.body(for: model.step))
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            controls
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Button(model.step == .createFirstAlarm ? "Create an alarm" : "Continue") {
                model.advance()
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("onboardingContinue")

            if model.canSkip {
                Button("Skip for now") { model.skip() }
                    .accessibilityIdentifier("onboardingSkip")
                    .accessibilityHint("You can add an alarm any time later")
            }
        }
    }

    private static func title(for step: OnboardingStep) -> String {
        switch step {
        case .welcome: "Welcome to Alarm Agent"
        case .enableAlarms: "Turn on alarms"
        case .createFirstAlarm: "Add your first alarm"
        case .ready: "You’re all set"
        }
    }

    private static func body(for step: OnboardingStep) -> String {
        switch step {
        case .welcome:
            "Reliable alarms first. Everything else is optional and asked for later, in context."
        case .enableAlarms:
            "Alarm Agent needs alarms and notifications so it can reliably wake you."
        case .createFirstAlarm: "Add one now, or skip and add it whenever you like."
        case .ready: "Your alarms are ready. Optional features can be enabled any time in Settings."
        }
    }
}
