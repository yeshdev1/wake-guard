import Foundation

/// A constrained confidence band for an AI proposal — never a raw score
/// (SAFETY_INVARIANTS #26).
enum ConfidenceBand: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case low
    case medium
    case high
}

/// The kind of recorded, deterministic factor a proposal's explanation is
/// derived from (SAFETY_INVARIANTS #32 — explanations come from recorded
/// factors, not invented reasons).
enum EvidenceKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case motionHistory
    case sleepEstimate
    case calendarEvent
    case timeZoneChange
    case userPreference
}

/// A reference to a recorded factor behind a proposal — an identifier for the
/// factor, not the raw sensitive data itself.
struct EvidenceReference: Codable, Sendable, Equatable, Hashable {
    let kind: EvidenceKind
    let reference: String
}

/// Metadata about the model/provider that produced a proposal. MVP is on-device
/// only (ADR-004).
struct ModelProviderMetadata: Codable, Sendable, Equatable, Hashable {
    let providerName: String
    let modelIdentifier: String
    let isOnDevice: Bool
}

/// An advisory, AI-produced suggestion. It is **not executable**: it only carries
/// a `proposedCommand` plus a human-readable explanation, evidence references, a
/// confidence band, an expiry, and provider metadata. Only the policy engine
/// (WG-028) may authorize turning the proposal into an executable `AlarmCommand`
/// (SAFETY_INVARIANTS #4, #5). It is deliberately a distinct type from
/// `AlarmCommand` so the two can never be confused, and it exposes no method that
/// executes or mutates anything.
struct AlarmProposal: Codable, Sendable, Equatable, Hashable {
    let proposedCommand: AlarmCommand
    let explanation: String
    let evidenceReferences: [EvidenceReference]
    let confidence: ConfidenceBand
    let expiresAt: Date
    let provider: ModelProviderMetadata

    /// Whether the proposal has expired as of `now` (callers pass an injected
    /// clock's time). An expired proposal must not be acted on.
    func isExpired(at now: Date) -> Bool {
        now >= expiresAt
    }
}
