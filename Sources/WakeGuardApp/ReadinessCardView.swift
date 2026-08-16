import SwiftUI

/// Presents a `ReadinessAssessment` as a gentle, fully-grounded explanation (WG-126). Every factor line
/// comes from a recorded factor (`ReadinessExplanation`), the **certainty** and any **missing inputs** are
/// shown, and a "not a diagnosis" note is always present. Design-system only, no color-only signal (each
/// line pairs an SF Symbol with text), stable a11y identifiers. Holds no alarm authority.
struct ReadinessCardView: View {
    let assessment: ReadinessAssessment
    /// Last night's mid-sleep interruptions (WG-309), or `nil` when there is no sleep data. Coarse by
    /// design — a count and a total, no times (#41).
    var interruptions: SleepInterruptions?

    private var explanation: ReadinessExplanation { ReadinessExplanation.from(assessment) }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Morning readiness")
                .font(DesignSystem.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            Text(explanation.summary)
                .font(DesignSystem.Typography.body)
                .accessibilityIdentifier("readinessSummary")

            Text(explanation.certaintyNote)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("readinessCertainty")

            ForEach(explanation.factorStatements, id: \.factor) { statement in
                Label(statement.text, systemImage: icon(for: statement.factor))
                    .font(DesignSystem.Typography.body)
                    .accessibilityIdentifier("readinessFactor.\(statement.factor.rawValue)")
            }

            if let interruptions {
                Label(interruptionText(interruptions), systemImage: interruptionIcon(interruptions))
                    .font(DesignSystem.Typography.body)
                    .accessibilityIdentifier("readinessInterruptions")
            }

            if !explanation.missingInputs.isEmpty {
                Label(missingText, systemImage: "questionmark.circle")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .accessibilityIdentifier("readinessMissing")
            }

            Text("A sleep estimate to help you plan — not a diagnosis.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("readinessDisclaimer")
        }
        .padding(DesignSystem.Spacing.lg)
    }

    private var missingText: String {
        let names = explanation.missingInputs.map(ReadinessExplanation.label(for:)).joined(
            separator: ", ")
        return "We don't have enough data yet for: \(names)."
    }

    private func icon(for factor: ReadinessFactorKind) -> String {
        switch factor {
        case .sleepDuration: "bed.double"
        case .sleepConsistency: "clock"
        case .sleepDebt: "chart.line.downtrend.xyaxis"
        }
    }

    /// Gentle, factual interruption line — a wake-up count and rounded awake minutes, no times (#41), no
    /// judgement. A slept-through night is stated positively; the icon differs so it isn't colour-only.
    private func interruptionText(_ interruptions: SleepInterruptions) -> String {
        guard interruptions.awakenings >= 1 else { return "Slept through — no interruptions." }
        let wakeUps =
            interruptions.awakenings == 1 ? "1 wake-up" : "\(interruptions.awakenings) wake-ups"
        let minutes = Int((interruptions.totalAwake / 60).rounded())
        let awake = minutes >= 1 ? "\(minutes) min awake" : "under a minute awake"
        return "\(wakeUps) · \(awake)"
    }

    private func interruptionIcon(_ interruptions: SleepInterruptions) -> String {
        interruptions.awakenings >= 1 ? "sunrise" : "moon.zzz"
    }
}
