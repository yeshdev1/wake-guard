import SwiftUI

/// The tomorrow-plan recommendation screen (WG-146). The **existing alarm is always shown** (never hidden
/// by a suggestion); the recommendation states its **reason** and **buffer** breakdown; and applying
/// requires an **explicit action** — the "Use this wake time" button calls `onApply` (wired by composition
/// to the policy engine, #6-gated for a critical change). The view holds no alarm authority itself.
/// Design-system only, no color-only signal, stable a11y IDs.
struct TomorrowPlanView: View {
    let presentation: TomorrowPlanPresentation
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Tomorrow's wake plan")
                .font(DesignSystem.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            Label(existingAlarmText, systemImage: "alarm")
                .font(DesignSystem.Typography.body)
                .accessibilityIdentifier("tomorrowPlanExistingAlarm")

            if let recommendation = presentation.recommendation {
                card(recommendation)
            } else {
                Text("There are no events to plan around tomorrow, so there's no suggestion.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .accessibilityIdentifier("tomorrowPlanNoRecommendation")
            }
        }
        .padding(DesignSystem.Spacing.lg)
    }

    private var existingAlarmText: String {
        presentation.existingAlarmRing.map { "Current alarm: \(timeText($0))" }
            ?? "No alarm set yet."
    }

    private func card(_ recommendation: TomorrowPlanPresentation.Recommendation) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Suggested wake time: \(timeText(recommendation.recommendedWake))")
                .font(DesignSystem.Typography.cardTitle)
                .accessibilityIdentifier("tomorrowPlanRecommendedWake")
            Text(recommendation.reason)
                .accessibilityIdentifier("tomorrowPlanReason")
            Text(recommendation.confidenceNote)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("tomorrowPlanConfidence")

            ForEach(recommendation.buffers, id: \.label) { buffer in
                Label("\(buffer.label): \(buffer.minutes) min", systemImage: "clock")
                    .font(DesignSystem.Typography.caption)
            }

            Button("Use this wake time", action: onApply)
                .accessibilityIdentifier("tomorrowPlanApply")
                .accessibilityHint(
                    "Sets an alarm at the suggested time. Your current alarm stays until you do.")
        }
        .font(DesignSystem.Typography.body)
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
