import Foundation

/// One sentence of the readiness explanation, **tagged with the recorded factor it describes** (WG-126).
/// Because every statement carries a `ReadinessFactorKind` drawn from the assessment's factors, the UI
/// can never show a claim that isn't grounded in a recorded factor (#32).
struct ReadinessStatement: Sendable, Equatable, Hashable {
    let factor: ReadinessFactorKind
    let text: String
}

/// A nonjudgmental, fully-grounded explanation of a `ReadinessAssessment` (WG-126). Every factor
/// statement maps to a recorded factor; **uncertainty** and **missing inputs** are surfaced explicitly;
/// the copy is gentle and never a diagnosis (#39). Descriptive content only — the SwiftUI view renders it.
struct ReadinessExplanation: Sendable, Equatable {
    /// The overall, gentle summary (from the level), or an honest "not enough data yet".
    let summary: String
    /// How much to trust it (from the certainty) — the **uncertainty** display.
    let certaintyNote: String
    /// One statement per **present** factor, each grounded in that recorded factor.
    let factorStatements: [ReadinessStatement]
    /// The factors we have **no data** for — surfaced, not silently omitted.
    let missingInputs: [ReadinessFactorKind]

    static func from(_ assessment: ReadinessAssessment) -> ReadinessExplanation {
        let present = Set(assessment.factors.map(\.kind))
        return ReadinessExplanation(
            summary: summary(for: assessment.level),
            certaintyNote: certaintyNote(for: assessment.certainty, hasData: !present.isEmpty),
            factorStatements: assessment.factors.map {
                ReadinessStatement(factor: $0.kind, text: statement(for: $0))
            },
            missingInputs: ReadinessFactorKind.allCases.filter { !present.contains($0) })
    }

    /// A user-facing label for a factor (also used to name a missing input).
    static func label(for factor: ReadinessFactorKind) -> String {
        switch factor {
        case .sleepDuration: "last night's sleep"
        case .sleepConsistency: "sleep consistency"
        case .sleepDebt: "recent sleep debt"
        }
    }

    // MARK: gentle, grounded copy

    private static func summary(for level: ReadinessLevel?) -> String {
        switch level {
        case .none: "There isn't enough sleep data yet to estimate how rested you are."
        case .good: "You're likely well-rested today."
        case .moderate: "You're moderately rested today."
        case .low: "You might be a little low on rest today — it's a good day to take it easy."
        }
    }

    private static func certaintyNote(for certainty: ReadinessCertainty, hasData: Bool) -> String {
        guard hasData else {
            return "Add a few nights of sleep data and this will get more useful."
        }
        switch certainty {
        case .high: return "Based on your recent sleep."
        case .moderate: return "Based on some of your recent sleep data."
        case .low: return "Based on limited data, so treat this as a rough guess."
        }
    }

    /// A gentle, grounded sentence for a present factor — a higher contribution reads positively, a lower
    /// one reads as a soft observation, never a judgement.
    private static func statement(for factor: ReadinessFactor) -> String {
        let rested = factor.contribution >= 0.75
        switch factor.kind {
        case .sleepDuration:
            return rested
                ? "You slept close to your target last night."
                : "Last night's sleep was a little short of your target."
        case .sleepConsistency:
            return rested
                ? "Your sleep timing has been fairly steady."
                : "Your sleep timing has varied a bit lately."
        case .sleepDebt:
            return rested
                ? "You're not carrying much sleep debt."
                : "You've built up a little sleep debt recently."
        }
    }
}
