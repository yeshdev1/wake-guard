import Foundation

/// Whether a habit suggestion is safe to show **everyone** without personalization (WG-127). Only
/// `generallySafe` behavioural tips are surfaced; `contraindicationSensitive` ones (anything needing
/// medical judgement — supplements, medication, intense exercise, fasting…) are **excluded** and are not
/// present in the curated library at all. The tag makes the exclusion structural + defensively filterable.
enum HabitSafety: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case generallySafe
    case contraindicationSensitive
}

/// One curated, evidence-informed sleep-hygiene suggestion (WG-127). **Static/curated** — never
/// AI-generated — general behavioural guidance framed as support, **not treatment** (#39). Each maps to
/// the readiness factor it helps (WG-125).
struct HabitSuggestion: Sendable, Equatable, Hashable, Identifiable {
    let id: String
    /// The readiness factor this habit supports.
    let factor: ReadinessFactorKind
    let headline: String
    let detail: String
    /// Why it helps, in plain terms — general sleep-hygiene rationale, no medical/treatment claim.
    let evidenceNote: String
    let safety: HabitSafety
}

/// A static, curated library of generally-safe sleep-hygiene suggestions (WG-127). Contains **only**
/// behavioural tips that are safe for everyone — no supplements, medication, or anything requiring
/// medical judgement — so nothing needs personalization to be safe, and no suggestion makes a treatment
/// claim (#39). Accessors additionally filter out any contraindication-sensitive entry (defense in depth).
enum HabitLibrary {

    static let curated: [HabitSuggestion] = [
        HabitSuggestion(
            id: "steady-schedule", factor: .sleepConsistency,
            headline: "Aim for a steady schedule",
            detail:
                "Try to go to bed and wake up around the same time each day, weekends included.",
            evidenceNote: "Regular timing helps your body clock stay in rhythm.",
            safety: .generallySafe),
        HabitSuggestion(
            id: "morning-daylight", factor: .sleepConsistency,
            headline: "Catch some morning daylight",
            detail: "A little natural light soon after you wake can help you feel alert.",
            evidenceNote: "Morning light is one of the strongest cues for your body clock.",
            safety: .generallySafe),
        HabitSuggestion(
            id: "wind-down", factor: .sleepDuration,
            headline: "Give yourself a wind-down",
            detail: "A calm routine before bed — dim the lights, set screens aside — can make it "
                + "easier to drift off.",
            evidenceNote: "A gentler lead-up to bed can help you settle.",
            safety: .generallySafe),
        HabitSuggestion(
            id: "cool-dark-room", factor: .sleepDuration,
            headline: "Keep your room cool and dark",
            detail: "A cool, dark, quiet bedroom tends to support more restful sleep.",
            evidenceNote: "Cool and dark surroundings suit your natural sleep signals.",
            safety: .generallySafe),
        HabitSuggestion(
            id: "protect-wake-time", factor: .sleepDebt,
            headline: "Protect your wake time",
            detail:
                "Keeping a consistent wake time, even after a short night, helps things even out.",
            evidenceNote: "A steady wake time supports your rhythm as you catch up.",
            safety: .generallySafe),
        HabitSuggestion(
            id: "ease-evening-screens", factor: .sleepDebt,
            headline: "Ease off late-evening screens",
            detail:
                "Winding down away from bright screens in the last hour can help you fall asleep "
                + "sooner.",
            evidenceNote: "Less bright light late on can make it easier to nod off.",
            safety: .generallySafe),
    ]

    /// Generally-safe suggestions tagged for `factor` — contraindication-sensitive entries are filtered
    /// out (they should never be in `curated`, but the filter guarantees it).
    static func suggestions(
        for factor: ReadinessFactorKind, from library: [HabitSuggestion] = curated
    ) -> [HabitSuggestion] {
        library.filter { $0.safety == .generallySafe && $0.factor == factor }
    }

    /// Suggestions relevant to an assessment's **below-par** factors (contribution `< threshold`), so a
    /// tip is only offered where it could help. Generally-safe only.
    static func suggestions(
        for assessment: ReadinessAssessment, threshold: Double = 0.75,
        from library: [HabitSuggestion] = curated
    ) -> [HabitSuggestion] {
        let lowFactors = Set(assessment.factors.filter { $0.contribution < threshold }.map(\.kind))
        return library.filter { $0.safety == .generallySafe && lowFactors.contains($0.factor) }
    }
}
