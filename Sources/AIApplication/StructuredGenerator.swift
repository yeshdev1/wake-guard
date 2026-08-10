import Foundation

/// Turns raw on-device-model output into a **validated domain DTO** (WG-163). It invokes a
/// `LanguageModelProvider`, decodes the returned text as JSON into an `AISchema`, and structurally
/// validates it. Any non-JSON, undecodable, or out-of-bounds output **fails closed** to
/// `.malformedOutput`; **cancellation** and **refusal** propagate as typed `LanguageModelError`s so each
/// maps to a deterministic fallback (#33). It **never logs prompts or model output** (#41) — it holds and
/// forwards no sensitive text to any sink.
struct StructuredGenerator: Sendable {
    private let provider: any LanguageModelProvider

    init(provider: any LanguageModelProvider) {
        self.provider = provider
    }

    /// Generate and decode a `T`. Throws `.cancelled` if the task is cancelled around the call,
    /// `.malformedOutput` if the output can't be decoded/validated, or whichever typed failure the
    /// provider raises (`.refused`, `.unavailable`, `.timedOut`, …).
    func generate<T: AISchema>(
        _ type: T.Type, for request: LanguageModelRequest
    ) async throws(LanguageModelError) -> T {
        if Task.isCancelled { throw .cancelled }
        let raw = try await provider.generate(request)
        if Task.isCancelled { throw .cancelled }
        return try Self.decodeAndValidate(type, from: raw)
    }

    /// Strict, fail-closed decode: trimmed non-empty JSON → decode → structural `validate()`. Every failure
    /// mode collapses to `.malformedOutput` so a hostile or hallucinated output can never yield a partial
    /// or out-of-range DTO. Unknown JSON keys are ignored by the schema's decode (WG-161), so an injected
    /// extra field is inert.
    private static func decodeAndValidate<T: AISchema>(
        _ type: T.Type, from raw: String
    ) throws(LanguageModelError) -> T {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .malformedOutput }
        let decoded: T
        do {
            decoded = try JSONDecoder().decode(T.self, from: Data(trimmed.utf8))
            try decoded.validate()
        } catch {
            throw .malformedOutput
        }
        return decoded
    }
}
