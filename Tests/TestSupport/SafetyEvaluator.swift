import Foundation

@testable import WakeGuard

/// A single case whose actual result diverged from its expectation (WG-176) — the unit of a backlog fix.
struct EvaluationFailure: Sendable, Equatable {
    let caseID: String
    let category: EvaluationCategory
    let expected: ExpectedResult
    let actual: ExpectedResult

    /// A ready-to-file backlog line (WG-176: "failures produce backlog fixes").
    var backlogLine: String {
        "[eval] \(category.rawValue) case \(caseID): expected \(expected.rawValue), "
            + "got \(actual.rawValue)"
    }
}

/// The result of running the evaluation corpus (WG-176).
struct SafetyEvaluationReport: Sendable, Equatable {
    let scheduleCaseCount: Int
    let invalidScheduleCount: Int
    let groundingCaseCount: Int
    let unsupportedClaimCount: Int
    let failures: [EvaluationFailure]

    /// Fraction of schedule cases that produced a schedule which should have been rejected/clarified.
    var invalidScheduleRate: Double {
        scheduleCaseCount == 0 ? 0 : Double(invalidScheduleCount) / Double(scheduleCaseCount)
    }

    /// Fraction of grounding cases where an ungrounded claim/citation survived.
    var unsupportedClaimRate: Double {
        groundingCaseCount == 0 ? 0 : Double(unsupportedClaimCount) / Double(groundingCaseCount)
    }

    /// The backlog items a run produced — empty on a clean run.
    var backlog: [String] { failures.map(\.backlogLine) }
}

/// Runs the WG-175 corpus through the **deterministic** pipeline components and measures the invalid-
/// schedule and unsupported-claim rates (WG-176). It **performs no alarm mutation** — it calls only pure
/// functions (parser interpret, validator, permission policy, prompt safety, proposal interpret), never a
/// command processor or repository — so evaluating never changes an alarm.
enum SafetyEvaluator {

    static func evaluate(_ cases: [EvaluationCase], now: Date) throws -> SafetyEvaluationReport {
        var failures: [EvaluationFailure] = []
        var invalidSchedule = 0
        var unsupportedClaim = 0
        var scheduleCases = 0
        var groundingCases = 0

        for evalCase in cases {
            if evalCase.category == .ambiguousDate || evalCase.category == .timeZone {
                scheduleCases += 1
            }
            if evalCase.category == .missingContext { groundingCases += 1 }

            let actual = try actualResult(for: evalCase, now: now)
            guard actual != evalCase.expected else { continue }

            failures.append(
                EvaluationFailure(
                    caseID: evalCase.id, category: evalCase.category, expected: evalCase.expected,
                    actual: actual))
            // An "invalid schedule" is a schedule allowed where it should have been blocked.
            let expectedBlocked = evalCase.expected == .reject || evalCase.expected == .clarify
            if expectedBlocked, actual == .allow { invalidSchedule += 1 }
            if evalCase.category == .missingContext { unsupportedClaim += 1 }
        }

        return SafetyEvaluationReport(
            scheduleCaseCount: scheduleCases, invalidScheduleCount: invalidSchedule,
            groundingCaseCount: groundingCases, unsupportedClaimCount: unsupportedClaim,
            failures: failures)
    }

    /// Run one case through its matching deterministic component and classify the outcome.
    static func actualResult(for evalCase: EvaluationCase, now: Date) throws -> ExpectedResult {
        switch evalCase.input {
        case .alarmParse(let parse):
            return classify(parse)
        case .validation(let draft, let zoneID):
            return classifyValidation(draft: draft, zoneID: zoneID, now: now)
        case .criticalHandoff(let mode, let targetIsCritical, _):
            return classifyHandoff(mode: mode, targetIsCritical: targetIsCritical)
        case .injectionText(let text):
            return classifyInjection(text)
        case .tomorrowContext(let context):
            return try classifyContext(context)
        }
    }

    private static func classify(_ parse: AIAlarmParse) -> ExpectedResult {
        switch NaturalLanguageAlarmParser.interpret(parse) {
        case .preview: return .allow
        case .needsClarification: return .clarify
        case .modelUnavailable, .notUnderstood: return .noProposal
        }
    }

    private static func classifyValidation(
        draft: AlarmDraftPreview, zoneID: String, now: Date
    ) -> ExpectedResult {
        switch AlarmIntentValidator().validate(draft, timeZoneIdentifier: zoneID, now: now) {
        case .valid: return .allow
        case .rejected: return .reject
        }
    }

    private static func classifyHandoff(
        mode: AgentPermissionMode, targetIsCritical: Bool
    ) -> ExpectedResult {
        // The only actions are recommend-only / request-confirmation — neither applies silently, so a
        // critical change always requires the user.
        switch AgentActionPolicy().action(mode: mode, targetIsCritical: targetIsCritical) {
        case .recommendOnly, .requestConfirmation: return .requiresConfirmation
        }
    }

    private static func classifyInjection(_ text: String) -> ExpectedResult {
        let delimited = PromptSafety.delimit(text)
        let contained =
            occurrences(of: PromptSafety.openTag, in: delimited) == 1
            && occurrences(of: PromptSafety.closeTag, in: delimited) == 1
        return contained ? .inert : .allow
    }

    private static func classifyContext(_ context: TomorrowContext) throws -> ExpectedResult {
        // Cite a fabricated factor: if it survives grounding it becomes a proposal (a hallucination); for a
        // factor-free context it must collapse to no-proposal.
        let draft = AITomorrowPlanProposal(
            suggestedWakeHour: 6, suggestedWakeMinute: 0,
            groundedFactorIDs: ["fabricated", "readiness"], rationale: "r")
        let maxWake = try TimeOfDay(hour: 10, minute: 0)
        switch TomorrowProposalGenerator.interpret(
            draft, context: context, targetIsCritical: false, maxWake: maxWake)
        {
        case .proposal: return .allow
        case .noProposal: return .noProposal
        }
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
