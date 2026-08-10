import Foundation

/// A structured type the on-device model may emit (WG-161/163). The `StructuredGenerator` (WG-163) decodes
/// model output into an `AISchema`, then calls `validate()` to reject structurally-invalid values (fail
/// closed) before any *semantic* validation (WG-165) or policy evaluation. Conforming types carry no
/// alarm authority — they are inert data.
protocol AISchema: Decodable, Sendable {
    /// Structural validation only — numeric bounds and required shape. Throws to reject. The default is a
    /// no-op, for schemas whose Swift type already fully constrains their values.
    func validate() throws
}

extension AISchema {
    func validate() throws {}
}

// The five model-facing schemas (WG-161). Those with numeric bounds provide their own `validate()`; the
// rest use the no-op default.
extension AIAlarmIntent: AISchema {}
extension AIAlarmParse: AISchema {}
extension AITomorrowPlanProposal: AISchema {}
extension AIJournalExtraction: AISchema {}
extension AIExplanationDraft: AISchema {}
extension AIPolicyPreference: AISchema {}
