import SwiftUI

/// Presents a `ReadinessAssessment` as a gentle, fully-grounded explanation (WG-126). Every factor line
/// comes from a recorded factor (`ReadinessExplanation`), the **certainty** and any **missing inputs** are
/// shown, and a "not a diagnosis" note is always present. Design-system only, no color-only signal (each
/// line pairs an SF Symbol with text), stable a11y identifiers. Holds no alarm authority.
struct ReadinessCardView: View {
    /// The concluded sleep read: an assessment, or why there isn't one (WG-319). The card keeps its header,
    /// its movement section and its disclaimer either way — a failed *sleep* read must not take the
    /// always-on movement section down with it, which is the WG-318 defect one layer up.
    let readiness: ReadinessCardContent
    /// Last night's mid-sleep interruptions (WG-309), or `nil` when there is no sleep data. Coarse by
    /// design — a count and a total, no times (#41).
    var interruptions: SleepInterruptions?
    /// The "Movement overnight" section's state (WG-310/311/318): an estimate, a reason there isn't one, or
    /// still loading. One total value rather than an estimate and a reason as separate optionals — the
    /// section can then always render *something*, which is the whole point of WG-318.
    /// Required, **not** defaulted: a default re-opens at the construction seam exactly the hole the total
    /// type closed. A caller that forgot this would compile clean and render a permanent "Checking your
    /// movement…" with no query in flight — the spinner defect one layer up, and untested.
    var movement: MovementDisplayState

    /// The explanation, or `nil` when the read produced nothing to explain. Every sentence it carries is a
    /// statement about the user's sleep data, so it must not be built from an absence of data that was never
    /// established — which is why this is derived from the case rather than from an always-present
    /// assessment.
    private var explanation: ReadinessExplanation? {
        guard case .assessed(let assessment) = readiness else { return nil }
        return ReadinessExplanation.from(assessment)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Morning readiness")
                .font(DesignSystem.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            // Exhaustive over a total value: there is no branch in which the card states nothing about the
            // sleep read, and no branch in which it states something the read did not establish.
            switch readiness {
            case .assessed: assessedSection()
            case .unavailable(let reason): unavailableSection(reason)
            }

            if let interruptions {
                Label(interruptionText(interruptions), systemImage: interruptionIcon(interruptions))
                    .font(DesignSystem.Typography.body)
                    .accessibilityIdentifier("readinessInterruptions")
            }

            // The movement summary is always shown when motion data is available (WG-312) — alongside any
            // HealthKit sleep data, not only as a fallback — and is never folded into the score above.
            // When there is no estimate the section stays and says *why* (WG-318): it used to disappear
            // entirely, so "no motion hardware", "access is off" and "not enough data" all looked the same.
            // Exhaustive over a total state: there is no "neither" branch to fall through, which is how the
            // section used to end up rendering nothing at all.
            switch movement {
            case .loading: movementLoadingSection()
            case .available(let disturbances, let rest):
                movementSection(disturbances: disturbances, rest: rest)
            case .unavailable(let reason): movementUnavailableSection(reason)
            }

            // Bound to `explanation`, so it cannot appear on a read that returned nothing. Naming each
            // factor as individually absent is a strictly *more specific* claim than the summary, and it was
            // the third false sentence the cold-open degrade put on screen.
            if let explanation, !explanation.missingInputs.isEmpty {
                Label(missingText(explanation), systemImage: "questionmark.circle")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .accessibilityIdentifier("readinessMissing")
            }

            // Outside both switches on purpose: the note is present in **every** branch (#39,
            // PRODUCT_SPEC.md:65). That makes its subject a claim about the *screen*, not about this card —
            // the earlier "A sleep estimate to help you plan…" asserted an estimate that is not there on the
            // `.unavailable` branch, or on an iPad where the movement section is unavailable too, leaving a
            // card that disclaims an artefact none of it contains. Third string on this branch to be written
            // for one state and reused in another; the fix is the noun, never removing the note.
            Text("Sleep estimates here help you plan — they are not a diagnosis.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("readinessDisclaimer")
        }
        .padding(DesignSystem.Spacing.lg)
    }

    /// The readiness explanation itself: a summary, how much to trust it, and one line per recorded factor.
    /// Rendered only for a read that **answered**, so every sentence in it is grounded in data the query
    /// actually returned.
    @ViewBuilder private func assessedSection() -> some View {
        if let explanation {
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
        }
    }

    /// A plain statement that the read failed, in place of the explanation (WG-319). Says what happened and
    /// asks the user to change nothing — it never blames them, never claims their data is missing, and never
    /// implies the alarm is affected, this card being advisory and touching no alarm state. Paired with an
    /// icon so the state isn't conveyed by absence or colour alone, matching the movement section's
    /// treatment of the same epistemic state.
    @ViewBuilder private func unavailableSection(_ reason: ReadinessUnavailability) -> some View {
        Label(reason.message, systemImage: reason.icon)
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            .accessibilityIdentifier("readinessUnavailableReason")
    }

    private func missingText(_ explanation: ReadinessExplanation) -> String {
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

    /// The header, in place, with an explicit "working on it" while the motion query runs. The card appears
    /// before that query returns, so without this the section is empty on every cold open — indistinguishable
    /// from the vanished section WG-318 removed. Says only that it is checking: no result is known yet, so
    /// any other wording would be a guess. A `ProgressView` conveys progress to VoiceOver as well as visually.
    @ViewBuilder private func movementLoadingSection() -> some View {
        Divider()
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Movement overnight")
                .font(DesignSystem.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("readinessMovementHeader")
            ProgressView("Checking your movement…")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("readinessMovementLoading")
        }
    }

    /// The same section header, kept in place, with a plain statement of why there is nothing under it
    /// (WG-318). Never blames the user, never implies the alarm is affected — this card is advisory and
    /// touches no alarm state. Paired with an icon so the state isn't conveyed by absence alone.
    @ViewBuilder private func movementUnavailableSection(_ reason: MovementUnavailability)
        -> some View
    {
        Divider()
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Movement overnight")
                .font(DesignSystem.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("readinessMovementHeader")
            Label(reason.message, systemImage: reason.icon)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("readinessMovementUnavailable")
        }
    }

    /// The always-on **Movement overnight** section (WG-310/311/312): a rest-window estimate and a
    /// disturbance estimate from motion history, shown alongside any HealthKit sleep data, under **one**
    /// explicit "estimated from movement" caveat so neither is mistaken for measured sleep. Its own header +
    /// divider make it a distinct section, not a sleep claim. Each line pairs an SF Symbol with text (not
    /// colour alone). Supplemental — never folded into the readiness score above.
    @ViewBuilder private func movementSection(disturbances: SleepDisturbances, rest: TimeInterval)
        -> some View
    {
        Divider()
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Movement overnight")
                .font(DesignSystem.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("readinessMovementHeader")
            // Not optional: the rest window comes from the same samples and the same night as the
            // disturbance count, so "one but not the other" was never a reachable state.
            Label(
                MovementEstimateCopy.restText(rest),
                systemImage: MovementEstimateCopy.restIcon
            )
            .font(DesignSystem.Typography.body)
            .accessibilityIdentifier("readinessRestEstimate")
            Label(
                MovementEstimateCopy.disturbanceText(disturbances),
                systemImage: MovementEstimateCopy.disturbanceIcon
            )
            .font(DesignSystem.Typography.body)
            .accessibilityIdentifier("readinessDisturbances")
            Text("Estimated from movement — not measured sleep.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("readinessMotionCaveat")
        }
    }

}
