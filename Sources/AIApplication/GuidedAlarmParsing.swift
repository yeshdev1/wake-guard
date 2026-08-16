import Foundation

/// The on-device **guided-generation** port for the describe-alarm parse (WG-301). Where the text
/// `LanguageModelProvider` asks the model for JSON and decodes it, this asks Apple's Foundation Models to
/// generate the parse **constrained to the schema at generation time** (`@Generable`) — the model cannot
/// emit an off-schema value, satisfying "constrained structured outputs" (#26) natively and more reliably
/// on the small on-device model. Read-only and value-producing only: it returns a validated `AIAlarmParse`
/// and holds no alarm authority — no tools, no AlarmKit, no persistence (#1/#30). Errors are the same
/// coarse typed `LanguageModelError` taxonomy as the text path, so the caller's fallback (#33) is uniform.
///
/// The concrete implementation lives in AIInfrastructure (the only importer of FoundationModels), so this
/// application/domain layer never sees the framework (architecture rule: Apple frameworks behind protocols).
protocol GuidedAlarmParsing: Sendable {
    func parseAlarm(from text: String) async throws(LanguageModelError) -> AIAlarmParse
}
