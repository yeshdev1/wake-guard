import Foundation

/// A **bounded, advisory** tomorrow-wake proposal (WG-168). It is emphatically **not a command**: it holds
/// a suggested wake time, the **real** context factors it is grounded in, a rationale, and whether applying
/// it needs explicit confirmation — but **no `AlarmCommand`, no criticality, and no authority**. It reaches
/// an alarm only if the user accepts it and `AlarmPolicyEngine` authorizes it (WG-172); it never mutates
/// anything by itself (#30/#31).
struct TomorrowProposal: Sendable, Equatable, Hashable {
    let suggestedWake: TimeOfDay
    /// Only factor IDs that are actually present in the context — fabricated citations are dropped (#32).
    let groundedFactors: [TomorrowFactorID]
    let rationale: String
    /// `true` when the change would affect a **critical** alarm — the UI/policy must confirm it (#6).
    let requiresConfirmation: Bool
}

/// The result of asking the Tomorrow Agent for a proposal (WG-168).
enum TomorrowProposalOutcome: Sendable, Equatable, Hashable {
    case proposal(TomorrowProposal)
    /// No safe, grounded proposal — the model was unavailable, cited no real factor, produced an
    /// out-of-bounds time, or suggested waking **later** than the deterministic latest-safe-wake. The
    /// deterministic no-op fallback (#33): the existing alarm is unchanged.
    case noProposal
}

/// Generates a tomorrow-wake proposal from the minimized context (WG-168). The model suggests; a
/// **deterministic** post-step enforces the safety envelope: it keeps only citations that name a **real**
/// context factor, rejects a suggestion that would wake the user **later** than the latest safe wake, and
/// marks a critical-alarm change as requiring confirmation. The output is always a bounded proposal or a
/// no-op — never a command.
struct TomorrowProposalGenerator: Sendable {
    private let generator: StructuredGenerator

    init(generator: StructuredGenerator) {
        self.generator = generator
    }

    func propose(
        from context: TomorrowContext, targetIsCritical: Bool, maxWake: TimeOfDay
    ) async -> TomorrowProposalOutcome {
        let draft: AITomorrowPlanProposal
        do {
            draft = try await generator.generate(
                AITomorrowPlanProposal.self, for: Self.request(for: context))
        } catch {
            return .noProposal
        }
        return Self.interpret(
            draft, context: context, targetIsCritical: targetIsCritical, maxWake: maxWake)
    }

    /// Deterministic safety envelope over the model's draft. Pure and fully testable. The upper bound is
    /// **always present**: the deterministic latest-safe-wake when the context has it, otherwise the
    /// conservative `maxWake` cap — so a proposal can never nudge the user to wake later than is safe, even
    /// when there is no calendar obligation (calendar not granted, or an empty day). An unparseable
    /// latest-safe-wake value fails **closed** to the cap, never open.
    static func interpret(
        _ draft: AITomorrowPlanProposal, context: TomorrowContext, targetIsCritical: Bool,
        maxWake: TimeOfDay
    ) -> TomorrowProposalOutcome {
        guard
            let wake = try? TimeOfDay(
                hour: draft.suggestedWakeHour, minute: draft.suggestedWakeMinute)
        else { return .noProposal }

        // Keep only citations that name a factor actually in the context (deduped, order-preserving).
        var seen = Set<TomorrowFactorID>()
        let grounded = draft.groundedFactorIDs
            .compactMap(TomorrowFactorID.init(rawValue:))
            .filter { context.factorIDs.contains($0) && seen.insert($0).inserted }
        guard !grounded.isEmpty else { return .noProposal }

        // Never propose waking later than the upper bound — the calendar-derived latest-safe-wake if
        // present and parseable, else the conservative `maxWake` cap (so the bound is never absent).
        let latestFromContext = context.value(for: .latestSafeWake).flatMap(Self.time(fromHHmm:))
        let upperBound = latestFromContext ?? maxWake
        guard wake <= upperBound else { return .noProposal }

        return .proposal(
            TomorrowProposal(
                suggestedWake: wake, groundedFactors: grounded, rationale: draft.rationale,
                requiresConfirmation: targetIsCritical))
    }

    private static func time(fromHHmm text: String) -> TimeOfDay? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return nil
        }
        return try? TimeOfDay(hour: hour, minute: minute)
    }

    /// Renders the minimized context into a prompt. Lists the available factors (id = value) and the
    /// unavailable sources, and constrains the model to **cite only these factor IDs** and to output the
    /// bounded schema — it is advisory, never a command.
    static func request(for context: TomorrowContext) -> LanguageModelRequest {
        let factorLines = context.factors.map { "\($0.id.rawValue) = \($0.value)" }.joined(
            separator: "\n")
        let unavailable = context.unavailableSources.map(\.rawValue).joined(separator: ", ")
        let system = """
            You suggest a wake time for tomorrow from the factors below. This is ADVISORY only — you never \
            change an alarm; the user and the app's policy decide.
            Output JSON: suggestedWakeHour (0-23), suggestedWakeMinute (0-59), groundedFactorIDs (an array \
            of the factor IDs your suggestion relies on), rationale (one short sentence).
            Cite ONLY these factor IDs; never invent one:
            \(factorLines.isEmpty ? "(none available)" : factorLines)
            Unavailable sources (no data): \(unavailable.isEmpty ? "none" : unavailable)
            Never suggest waking later than latestSafeWake if it is present. Output ONLY the JSON.
            """
        return LanguageModelRequest(
            systemPrompt: system, userPrompt: "Suggest tomorrow's wake time.")
    }
}
