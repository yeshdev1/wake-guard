import Foundation

/// The wellness safety copy (WG-128). Plain-language statements that WakeGuard is a **wellness, not
/// medical** tool (#39): it doesn't diagnose, treat, or prevent anything, its figures are estimates, and
/// it doesn't handle urgent or medical concerns. Shown wherever wellness content appears.
enum WellnessSafetyCopy {
    /// The app's scope — general wellness, explicitly **not medical**.
    static let scope =
        "WakeGuard offers general sleep and wellness information to help you plan your day. It is not "
        + "medical advice and does not diagnose, treat, or prevent any condition."

    /// Figures are estimates, not clinical measurements.
    static let estimatesNotClinical =
        "Sleep figures are rough estimates from your device, not clinical measurements."

    /// The standing notice + the **medical-emergency** referral: urgent/medical concerns are out of
    /// scope, and the assistant will not try to handle them.
    static let urgentSymptoms =
        "WakeGuard can't help with urgent or medical concerns, and its assistant won't try to. If "
        + "something about your health worries you, please talk to a healthcare professional. In an "
        + "emergency, contact your local emergency services."

    /// The **mental-health-crisis** referral — warmer and non-dismissive, pointing to real support rather
    /// than only "emergency services". (A locale-correct crisis-line **number** is an E11 localization
    /// follow-up; this copy stays locale-neutral for now.)
    static let mentalHealthCrisis =
        "It sounds like you may be going through something really hard, and WakeGuard isn't the right "
        + "tool for this — but you don't have to face it alone. Please reach out to a crisis line or a "
        + "mental health professional. If you might be in danger, contact your local emergency services "
        + "right away."
}

/// Which safe referral an out-of-scope interaction warrants (WG-128).
enum UrgentReferralKind: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case medicalEmergency
    case mentalHealthCrisis
}

/// Whether a wellness interaction is in scope for the assistant, or must be routed to a safe referral
/// (WG-128). A `referral` must **never** reach the AI.
enum WellnessInteractionScope: Sendable, Equatable, Hashable {
    case wellness
    case referral(UrgentReferralKind)
}

/// A conservative pre-filter that keeps **urgent or medical** concerns away from the wellness assistant
/// (WG-128). If the text mentions a crisis or emergency indicator, the interaction is out of scope and
/// the app shows the matching referral copy — the AI never handles it. It is the deterministic **first
/// line** the E09 assistant path must route through (WG-172/WG-173 must call this on every free-text
/// input before the model, and never invoke the provider for a `.referral`), alongside the model's own
/// instructions to decline medical topics.
///
/// It **errs toward referral** (a false positive is a safe over-referral), matches by lowercased
/// substring (catching inflections), checks the **crisis** list first (so distress gets the warmer copy),
/// and is **not** medical triage — it matches distress/emergency *intent*, never diagnoses a symptom. It
/// never claims to detect every case; the model instructions are the second layer.
enum UrgentSymptomPolicy {
    /// Mental-health-crisis / self-harm intent — checked first so it gets the crisis referral.
    static let crisisIndicators = [
        "suicid", "kill myself", "want to die", "don't want to live", "do not want to live",
        "don't want to be here", "do not want to be here", "end my life", "end it all",
        "better off dead", "no reason to live", "self-harm", "self harm", "hurt myself",
        "harm myself",
    ]

    /// Physical medical-emergency indicators.
    static let emergencyIndicators = [
        "chest pain", "can't breathe", "cannot breathe", "not breathing", "shortness of breath",
        "heart attack", "stroke", "choking", "bleeding", "seizure", "unconscious", "unresponsive",
        "passed out", "collapsed", "allergic reaction", "anaphyla", "overdose", "overdosed",
        "emergency", "911", "999", "112",
    ]

    static func scope(of text: String) -> WellnessInteractionScope {
        let lowered = text.lowercased()
        if crisisIndicators.contains(where: lowered.contains) {
            return .referral(.mentalHealthCrisis)
        }
        if emergencyIndicators.contains(where: lowered.contains) {
            return .referral(.medicalEmergency)
        }
        return .wellness
    }

    /// The copy to show for a referral kind.
    static func referralCopy(for kind: UrgentReferralKind) -> String {
        switch kind {
        case .medicalEmergency: WellnessSafetyCopy.urgentSymptoms
        case .mentalHealthCrisis: WellnessSafetyCopy.mentalHealthCrisis
        }
    }
}
