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

    /// Strict, fail-closed decode: extract the JSON object → decode → structural `validate()`. Every failure
    /// mode collapses to `.malformedOutput` so a hostile or hallucinated output can never yield a partial
    /// or out-of-range DTO. Unknown JSON keys are ignored by the schema's decode (WG-161), so an injected
    /// extra field is inert.
    private static func decodeAndValidate<T: AISchema>(
        _ type: T.Type, from raw: String
    ) throws(LanguageModelError) -> T {
        guard let json = jsonObject(in: raw) else { throw .malformedOutput }
        let decoded: T
        do {
            decoded = try JSONDecoder().decode(T.self, from: Data(json.utf8))
            try decoded.validate()
        } catch {
            throw .malformedOutput
        }
        return decoded
    }

    /// Extract the first **balanced** top-level JSON object from raw model text (WG-296). On-device models
    /// routinely wrap the object in prose ("Here's the JSON: …") or a ```` ```json ```` fence, which the old
    /// exact-match decode rejected — the "it errored out" report. Scanning from the first `{` to its
    /// matching `}`, ignoring braces inside strings, recovers the object; no complete object ⇒ nil ⇒ fail
    /// closed. **Security:** recovering an embedded object grants no new capability — unknown keys stay
    /// inert (WG-161), a parsed draft is never critical (#31), the provider exposes no tools (#30), and the
    /// result is only a preview the user must still confirm. An injection payload without the required
    /// fields still fails to decode.
    static func jsonObject(in raw: String) -> String? {
        let characters = Array(raw)
        guard let start = characters.firstIndex(of: "{") else { return nil }
        var depth = 0
        var scan = StringScan()
        for index in start..<characters.count {
            let character = characters[index]
            if scan.consuming(character) { continue }  // inside a string literal — braces are inert
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return String(characters[start...index]) }
            }
        }
        return nil
    }

    /// Tracks whether the object scanner is inside a JSON string literal so that braces in string *values*
    /// don't change nesting depth. `consuming` returns true while the character is part of a string (its
    /// content or delimiting quotes), false for structural characters the scanner must weigh.
    private struct StringScan {
        private var inString = false
        private var escaped = false

        mutating func consuming(_ character: Character) -> Bool {
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                return true
            }
            if character == "\"" {
                inString = true
                return true
            }
            return false
        }
    }
}
