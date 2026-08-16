import Foundation

/// The honest, reason-aware message shown under the "Describe your alarm" card when on-device intelligence
/// isn't available (WG-302). It always tells the user what's going on and points them to **add manually**,
/// and only offers "Open Settings" when there's actually something to turn on (Apple Intelligence off).
/// Pure and testable — the header just renders it; there is no message when AI is available.
struct AlarmCreationHint: Sendable, Equatable {
    let message: String
    /// True only for `appleIntelligenceNotEnabled` — an ineligible device or a still-preparing model has
    /// nothing for the user to flip, so no Settings button is shown.
    let showsOpenSettings: Bool

    /// The hint for a decision, or `nil` when AI is available (no hint).
    static func hint(for decision: AIAvailabilityDecision) -> AlarmCreationHint? {
        guard let reason = decision.unavailabilityReason else { return nil }
        switch reason {
        case .appleIntelligenceNotEnabled:
            return AlarmCreationHint(
                message: "Smart setup uses Apple Intelligence, which is turned off. Turn it on in "
                    + "Settings › Apple Intelligence & Siri to describe alarms — or add one manually "
                    + "below.",
                showsOpenSettings: true)
        case .deviceNotEligible:
            return AlarmCreationHint(
                message:
                    "This iPhone doesn’t support Apple Intelligence, so describing alarms isn’t "
                    + "available. Add your alarm manually below — everything else works normally.",
                showsOpenSettings: false)
        case .modelNotReady:
            return AlarmCreationHint(
                message:
                    "Apple Intelligence is still setting up. You’ll be able to describe alarms "
                    + "once it’s ready — for now, add one manually below.",
                showsOpenSettings: false)
        case .unknown:
            return AlarmCreationHint(
                message: "Smart setup isn’t available right now. Add your alarm manually below.",
                showsOpenSettings: false)
        }
    }
}
