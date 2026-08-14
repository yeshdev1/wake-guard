import Foundation

/// User-facing copy describing AI availability in Settings (WG-162). Text only — the view pairs it with an
/// SF Symbol, never a color-only signal — and it **always** states that alarms are unaffected, so a user
/// who sees "AI off" is never left unsure whether their alarm still rings (#9).
struct AIAvailabilityStatusCopy: Sendable, Equatable, Hashable {
    let title: String
    let detail: String
    /// Always present: reassurance that alarms ring with or without on-device intelligence.
    let alarmsReassurance: String
    /// For the view's icon/label choice — not a color-only signal.
    let isAvailable: Bool
}

/// Maps an availability decision to Settings copy (WG-162). Every unavailable reason gets its own, honest
/// detail line (eligibility vs. a setting to flip vs. a model still preparing), and every case carries the
/// same alarms-unaffected reassurance.
enum AIAvailabilityStatusPresenter {
    static let alarmsReassurance = "Your alarms ring with or without on-device intelligence."

    static func copy(for decision: AIAvailabilityDecision) -> AIAvailabilityStatusCopy {
        guard let reason = decision.unavailabilityReason else {
            return AIAvailabilityStatusCopy(
                title: "On-device intelligence is on",
                detail:
                    "Suggestions are generated privately on this device. They are always advisory.",
                alarmsReassurance: alarmsReassurance, isAvailable: true)
        }
        return AIAvailabilityStatusCopy(
            title: title(for: reason), detail: detail(for: reason),
            alarmsReassurance: alarmsReassurance, isAvailable: false)
    }

    private static func title(for reason: ModelUnavailabilityReason) -> String {
        switch reason {
        case .modelNotReady: "On-device intelligence is preparing"
        case .deviceNotEligible, .appleIntelligenceNotEnabled, .unknown:
            "On-device intelligence is off"
        }
    }

    private static func detail(for reason: ModelUnavailabilityReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This device doesn’t support on-device intelligence. Alarm Agent uses its built-in logic instead."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings to enable private suggestions."
        case .modelNotReady:
            "The on-device model is still downloading or preparing. Suggestions resume once it’s ready."
        case .unknown:
            "On-device intelligence isn’t available right now. Alarm Agent uses its built-in logic instead."
        }
    }
}
