import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Reads the real on-device-model availability from Apple's Foundation Models framework and maps it onto
/// the domain `ModelAvailability` (WG-162). The one place `SystemLanguageModel` is touched for
/// availability, so domain code never imports FoundationModels. Read-only — it reports availability and
/// nothing else (no generation, no alarm authority).
///
/// If FoundationModels is unavailable in the SDK, the adapter **fails closed** to
/// `.unavailable(.modelNotReady)`: AI features stay off and every consumer uses its deterministic path.
struct FoundationModelsAvailabilityAdapter: ModelAvailabilityProviding {

    func currentAvailability() -> ModelAvailability {
        #if canImport(FoundationModels)
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                return .unavailable(Self.map(reason))
            }
        #else
            return .unavailable(.modelNotReady)
        #endif
    }

    #if canImport(FoundationModels)
        private static func map(
            _ reason: SystemLanguageModel.Availability.UnavailableReason
        ) -> ModelUnavailabilityReason {
            switch reason {
            case .deviceNotEligible: .deviceNotEligible
            case .appleIntelligenceNotEnabled: .appleIntelligenceNotEnabled
            case .modelNotReady: .modelNotReady
            @unknown default: .unknown
            }
        }
    #endif
}
