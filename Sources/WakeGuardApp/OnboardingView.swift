import SwiftUI

/// The progressive onboarding screen (WG-200). It gathers **only alarm essentials** (notifications +
/// alarms), then offers an optional first alarm the user can **skip** and still reach a usable app. Optional
/// data permissions (motion, location, health, calendar, cloud AI) are **not** requested here — they are
/// asked for later, in context. Design-system, accessibility-labelled.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    var onFinished: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text(Self.title(for: model.step))
                .font(DesignSystem.Typography.screenTitle)
                .accessibilityAddTraits(.isHeader)
            Text(Self.body(for: model.step))
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
            Spacer(minLength: 0)
            controls
        }
        .padding(DesignSystem.Spacing.lg)
        .onChange(of: model.isComplete) { _, complete in
            if complete { onFinished() }
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Button(model.step == .createFirstAlarm ? "Create an alarm" : "Continue") {
                model.advance()
            }
            .buttonStyle(.borderedProminent)
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
        case .welcome: "Welcome to WakeGuard"
        case .enableAlarms: "Turn on alarms"
        case .createFirstAlarm: "Add your first alarm"
        case .ready: "You’re all set"
        }
    }

    private static func body(for step: OnboardingStep) -> String {
        switch step {
        case .welcome:
            "Reliable alarms first. Everything else is optional and asked for later, in context."
        case .enableAlarms: "WakeGuard needs alarms and notifications so it can reliably wake you."
        case .createFirstAlarm: "Add one now, or skip and add it whenever you like."
        case .ready: "Your alarms are ready. Optional features can be enabled any time in Settings."
        }
    }
}
