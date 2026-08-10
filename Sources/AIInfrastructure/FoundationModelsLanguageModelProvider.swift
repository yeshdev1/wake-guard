import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// The on-device `LanguageModelProvider` backed by Apple's Foundation Models (WG-163). It runs a
/// `LanguageModelSession` entirely on device (no network, no cloud), returning the model's text for the
/// `StructuredGenerator` to decode. The only place the generation API is touched, so domain code never
/// imports FoundationModels.
///
/// Errors are mapped to the coarse typed `LanguageModelError` taxonomy — a guardrail/refusal ⇒ `.refused`,
/// cancellation ⇒ `.cancelled`, missing assets/unavailable model ⇒ `.unavailable`, anything else ⇒
/// `.generationFailed` — so no raw provider error text escapes (#41) and every failure has a deterministic
/// fallback (#33). If FoundationModels is absent from the SDK, it fails closed to `.unavailable`.
struct FoundationModelsLanguageModelProvider: LanguageModelProvider {

    func generate(_ request: LanguageModelRequest) async throws(LanguageModelError) -> String {
        #if canImport(FoundationModels)
            return try await Self.respond(to: request)
        #else
            throw .unavailable
        #endif
    }

    #if canImport(FoundationModels)
        private static func respond(
            to request: LanguageModelRequest
        ) async throws(LanguageModelError) -> String {
            guard case .available = SystemLanguageModel.default.availability else {
                throw .unavailable
            }
            do {
                let session = LanguageModelSession(instructions: request.systemPrompt)
                let response = try await session.respond(to: request.userPrompt)
                return response.content
            } catch is CancellationError {
                throw .cancelled
            } catch let error as LanguageModelSession.GenerationError {
                throw Self.map(error)
            } catch {
                throw .generationFailed
            }
        }

        private static func map(_ error: LanguageModelSession.GenerationError) -> LanguageModelError
        {
            switch error {
            case .guardrailViolation, .refusal: .refused
            case .assetsUnavailable: .unavailable
            default: .generationFailed
            }
        }
    #endif
}
