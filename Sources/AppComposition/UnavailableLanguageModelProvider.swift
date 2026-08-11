import Foundation

/// A hermetic `LanguageModelProvider` for the in-memory graph (WG-160/166): it always reports the model as
/// unavailable, so previews/tests never touch on-device FoundationModels. The conversational create flow
/// then fails closed to the manual editor (#33). Production uses `FoundationModelsLanguageModelProvider`.
struct UnavailableLanguageModelProvider: LanguageModelProvider {
    func generate(_ request: LanguageModelRequest) async throws(LanguageModelError) -> String {
        throw .unavailable
    }
}
