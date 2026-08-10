import Foundation

/// Whether advisory AI features may run, given the on-device model's availability (WG-162). When AI is
/// disabled, every AI-consuming feature falls back to its **deterministic** path — the app never blocks on
/// AI. The decision carries **no alarm authority** (no command, no criticality, nothing alarm-scheduling
/// reads): an availability decision can turn *suggestions* off, never an *alarm* (#9, "no AI feature
/// blocks alarm use").
struct AIAvailabilityDecision: Sendable, Equatable, Hashable {
    /// `true` ⇒ AI features may run; `false` ⇒ use the deterministic fallback.
    let aiFeaturesEnabled: Bool
    /// Why AI is off, when it is off; `nil` when enabled.
    let unavailabilityReason: ModelUnavailabilityReason?

    static let enabled = AIAvailabilityDecision(aiFeaturesEnabled: true, unavailabilityReason: nil)

    static func disabled(_ reason: ModelUnavailabilityReason) -> AIAvailabilityDecision {
        AIAvailabilityDecision(aiFeaturesEnabled: false, unavailabilityReason: reason)
    }
}

/// The pure availability gate (WG-162). Maps model availability to a decision: `.available` ⇒ AI features
/// enabled; **any** unavailable state ⇒ AI off with the deterministic fallback. It is a total function
/// with no side effects, so its result is fully testable and never depends on hardware being present.
struct AIAvailabilityGate: Sendable {
    func decide(for availability: ModelAvailability) -> AIAvailabilityDecision {
        switch availability {
        case .available:
            return .enabled
        case .unavailable(let reason):
            return .disabled(reason)
        }
    }
}
