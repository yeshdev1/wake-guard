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
    /// A motion-based **estimate** of overnight disturbances (WG-310) — shown only as a *fallback* when
    /// HealthKit gives no interruptions, and clearly labelled as an estimate from movement.
    var estimatedDisturbances: SleepDisturbances?
    /// A motion-based **estimate** of the longest low-activity (rest) stretch overnight (WG-311), in
    /// seconds — supplemental context, never sleep and never a readiness factor.
    var estimatedRest: TimeInterval?

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
            } else if let estimatedDisturbances {
                motionFallback(disturbances: estimatedDisturbances, rest: estimatedRest)
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

    /// The motion fallback (WG-310/311): a rest-window estimate and a disturbance estimate for users without
    /// measured sleep, under **one** explicit "estimated from movement" caveat so neither is mistaken for
    /// measured sleep. Each line pairs an SF Symbol with text (not colour alone). This is supplemental — it
    /// is never folded into the readiness score above.
    @ViewBuilder private func motionFallback(disturbances: SleepDisturbances, rest: TimeInterval?)
        -> some View
    {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            if let rest {
                Label(restText(rest), systemImage: "moon.zzz")
                    .font(DesignSystem.Typography.body)
                    .accessibilityIdentifier("readinessRestEstimate")
            }
            Label(
                disturbanceText(disturbances), systemImage: "iphone.gen1.radiowaves.left.and.right"
            )
            .font(DesignSystem.Typography.body)
            .accessibilityIdentifier("readinessDisturbances")
            Text("Estimated from movement — not measured sleep.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("readinessMotionCaveat")
        }
    }

    private func disturbanceText(_ disturbances: SleepDisturbances) -> String {
        guard disturbances.pickups >= 1 else { return "No overnight movement detected." }
        let times = disturbances.pickups == 1 ? "1 time" : "\(disturbances.pickups) times"
        return "Phone moved \(times) overnight"
    }

    private func restText(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        guard totalMinutes >= 30 else { return "Little low-activity time overnight." }
        let (hours, minutes) = (totalMinutes / 60, totalMinutes % 60)
        let span =
            hours >= 1 ? (minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h") : "\(minutes)m"
        return "~\(span) of low activity overnight"
    }
}
