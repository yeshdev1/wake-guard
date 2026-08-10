import Foundation

/// Why the on-device model is unavailable (WG-162). Mirrors the Foundation Models unavailability reasons,
/// plus a fail-closed `.unknown` for any state a future OS adds — an unrecognized state is treated as
/// unavailable (AI off), never as available.
enum ModelUnavailabilityReason: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown
}

/// The on-device model's availability (WG-162). The infrastructure adapter maps the real
/// `SystemLanguageModel` state onto this domain enum, so domain code and tests never import
/// FoundationModels (architecture rule: Apple frameworks behind protocols).
enum ModelAvailability: Sendable, Equatable, Hashable {
    case available
    case unavailable(ModelUnavailabilityReason)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// A port that reports the current on-device-model availability (WG-162). Synchronous — the underlying OS
/// property is synchronous — and read-only: it can report availability but never generate, mutate, or
/// schedule anything.
protocol ModelAvailabilityProviding: Sendable {
    func currentAvailability() -> ModelAvailability
}
