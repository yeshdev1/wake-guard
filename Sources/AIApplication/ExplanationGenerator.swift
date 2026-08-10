import Foundation

/// One model-emitted claim: a single sentence tied to exactly one factor ID (WG-169). Claim-structured
/// (not one blob of prose) so grounding can be enforced **per claim** — a claim whose `factorID` is not a
/// real factor is dropped.
struct AIGroundedClaim: Sendable, Equatable, Hashable, Codable {
    let factorID: String
    let claim: String
}

/// The model's grounded-explanation output (WG-169): a list of per-claim citations.
struct AIExplanationClaims: Sendable, Equatable, Hashable, Codable {
    let claims: [AIGroundedClaim]
}

/// A known internal factor an explanation may cite (WG-169): a stable `id` and a coarse, non-sensitive
/// `value`. The generator's caller supplies these; only these IDs may be cited.
struct ExplanationFactor: Sendable, Equatable, Hashable {
    let id: String
    let value: String
}

/// A single grounded statement in the final explanation (WG-169) — display text tied to a **real** factor
/// ID. Inert text; carries no command.
struct GroundedStatement: Sendable, Equatable, Hashable {
    let factorID: String
    let text: String
}

/// A grounded explanation (WG-169): statements each tied to a real factor, plus whether the deterministic
/// template fallback produced it.
struct GroundedExplanation: Sendable, Equatable, Hashable {
    let statements: [GroundedStatement]
    let usedFallback: Bool

    var isEmpty: Bool { statements.isEmpty }
}

/// Generates a user-facing explanation whose **every claim cites an internal factor ID** (WG-169). The
/// model drafts claims; a deterministic step **drops any claim** that cites an ID which isn't a real
/// factor, so an ungrounded/hallucinated claim can never be shown. If the model is unavailable or **no**
/// claim survives grounding, a **deterministic template** fallback builds the explanation from the factors
/// alone — the feature always produces a safe, grounded result (#32/#33).
struct ExplanationGenerator: Sendable {
    private let generator: StructuredGenerator

    init(generator: StructuredGenerator) {
        self.generator = generator
    }

    func explain(factors: [ExplanationFactor]) async -> GroundedExplanation {
        guard !factors.isEmpty else {
            return GroundedExplanation(statements: [], usedFallback: true)
        }
        let known = Set(factors.map(\.id))
        do {
            let output = try await generator.generate(
                AIExplanationClaims.self, for: Self.request(for: factors))
            let grounded = output.claims
                .filter { known.contains($0.factorID) }
                .map { GroundedStatement(factorID: $0.factorID, text: $0.claim) }
            guard !grounded.isEmpty else { return Self.fallback(for: factors) }
            return GroundedExplanation(statements: grounded, usedFallback: false)
        } catch {
            return Self.fallback(for: factors)
        }
    }

    /// The deterministic template: one plainly-grounded statement per factor. Pure — same factors always
    /// yield the same explanation.
    static func fallback(for factors: [ExplanationFactor]) -> GroundedExplanation {
        GroundedExplanation(
            statements: factors.map {
                GroundedStatement(factorID: $0.id, text: "\($0.id) is \($0.value)")
            },
            usedFallback: true)
    }

    static func request(for factors: [ExplanationFactor]) -> LanguageModelRequest {
        let factorLines = factors.map { "\($0.id) = \($0.value)" }.joined(separator: "\n")
        let system = """
            Explain the recommendation using ONLY the factors below. Output JSON: claims (an array of \
            objects, each { "factorID": one of the factor IDs, "claim": one short sentence }).
            Every claim must cite exactly one of these factor IDs; never invent a factor:
            \(factorLines)
            Do not make medical or diagnostic statements. Output ONLY the JSON.
            """
        return LanguageModelRequest(
            systemPrompt: system, userPrompt: "Explain the recommendation.")
    }
}
