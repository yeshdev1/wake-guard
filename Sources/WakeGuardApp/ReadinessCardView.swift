import SwiftUI

/// Presents a `ReadinessAssessment` as a gentle, fully-grounded explanation (WG-126). Every factor line
/// comes from a recorded factor (`ReadinessExplanation`), the **certainty** and any **missing inputs** are
/// shown, and a "not a diagnosis" note is always present. Design-system only, no color-only signal (each
/// line pairs an SF Symbol with text), stable a11y identifiers. Holds no alarm authority.
struct ReadinessCardView: View {
    let assessment: ReadinessAssessment

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
}
