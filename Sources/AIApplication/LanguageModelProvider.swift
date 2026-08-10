import Foundation

/// A request to the on-device language model (WG-160). It carries **only prompt content** — no tools, no
/// function calls, no alarm-mutating capability (#1/#30). The provider can produce text and nothing else,
/// so the model can never act on an alarm; a proposal is decoded downstream (WG-163) and only the policy
/// engine may authorize it.
struct LanguageModelRequest: Sendable, Equatable, Hashable {
    /// The instruction/guardrail preamble (constant, app-authored).
    let systemPrompt: String
    /// The (possibly untrusted) user/content text to reason over.
    let userPrompt: String
}

/// The **typed** failures a language-model call can produce (WG-160). No raw provider error text is ever
/// surfaced (#41) — a failure is one of these coarse, safe cases, each of which the caller maps to a
/// deterministic fallback (#33).
enum LanguageModelError: Error, Sendable, Equatable, Hashable, CaseIterable {
    /// The model isn't available on this device (the WG-162 gate is closed).
    case unavailable
    /// The model declined to answer (a safety refusal) — treated as "no proposal".
    case refused
    case timedOut
    case cancelled
    /// The model produced output that couldn't be used.
    case malformedOutput
    /// A generic generation failure (no raw error text).
    case generationFailed
}

/// The on-device language-model boundary (WG-160). It **only generates text** — it exposes **no tools**
/// and cannot call AlarmKit, mutate persistence, or set criticality (#1/#30/#31); the sole capability is
/// turning a request into a String (or a **typed** failure). Structured decoding into domain DTOs is the
/// WG-163 adapter's job, and every proposed mutation still passes through `AlarmPolicyEngine`. On-device
/// by default (#34/#35). Typed throws make "typed result or typed failure" a compile-time guarantee.
protocol LanguageModelProvider: Sendable {
    func generate(_ request: LanguageModelRequest) async throws(LanguageModelError) -> String
}
