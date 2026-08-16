import Foundation

/// Turns recorded wake facts into **simple-English** text for the activity history (WG-299), on-device
/// only. It is a *narrator*, never a source: it feeds the deterministic facts to the grounded
/// `ExplanationGenerator` (every claim must cite a real factor, so nothing is invented, #32) and — if the
/// model is unavailable or nothing survives grounding — falls back to the deterministic `plainSummary`
/// (#33). It makes no medical or diagnostic statement (#39) and its prompts are never logged (#41).
struct AlarmActivityNarrator: Sendable {
    private let generator: ExplanationGenerator

    init(generator: ExplanationGenerator) {
        self.generator = generator
    }

    /// One friendly line describing a single wake — AI-phrased when available, else the deterministic
    /// `plainSummary`.
    func narrate(_ activity: AlarmActivity) async -> String {
        let explanation = await generator.explain(factors: Self.factors(for: activity))
        return Self.text(from: explanation) ?? activity.plainSummary
    }

    /// A short paragraph summarizing many recent wakes — AI-phrased when available, else a deterministic
    /// aggregate sentence.
    func summarize(_ activities: [AlarmActivity]) async -> String {
        let stats = AlarmActivitySummary(activities)
        guard !activities.isEmpty else { return stats.plainSummary }
        let explanation = await generator.explain(factors: stats.factors)
        return Self.text(from: explanation) ?? stats.plainSummary
    }

    /// Join a grounded explanation into a sentence, or nil to signal "use the deterministic fallback"
    /// (empty, or the generator's own template fallback — whose raw "id is value" text we never show).
    private static func text(from explanation: GroundedExplanation) -> String? {
        guard !explanation.usedFallback, !explanation.isEmpty else { return nil }
        return explanation.statements.map(\.text).joined(separator: " ")
    }

    private static func factors(for activity: AlarmActivity) -> [ExplanationFactor] {
        var factors = [
            ExplanationFactor(id: "outcome", value: outcomeValue(activity.outcome))
        ]
        if activity.walkRequired {
            factors.append(
                ExplanationFactor(
                    id: "steps", value: "\(activity.stepsWalked) of \(activity.requiredSteps)"))
            factors.append(
                ExplanationFactor(id: "duration", value: "\(activity.durationSeconds) seconds"))
        }
        return factors
    }

    private static func outcomeValue(_ outcome: AlarmActivityOutcome) -> String {
        switch outcome {
        case .walkedAndPassed: "completed the walk and turned the alarm off"
        case .tapAlternative: "turned the alarm off with the tap alternative"
        case .timedOut: "did not finish the walk in time; the alarm stayed on"
        case .interrupted: "the wake check was interrupted; the alarm stayed on"
        }
    }
}

/// Narrates a wake and stores it with the cached summary (WG-299) — the concrete `AlarmActivityRecording`
/// the challenge runtime calls at an outcome. Best-effort: narration falls back to deterministic text and
/// a store fault drops the one entry, never touching an alarm (#8/#9).
struct DefaultAlarmActivityRecorder: AlarmActivityRecording {
    private let narrator: AlarmActivityNarrator
    private let store: any AlarmActivityStore

    init(narrator: AlarmActivityNarrator, store: any AlarmActivityStore) {
        self.narrator = narrator
        self.store = store
    }

    func record(_ activity: AlarmActivity) async {
        let summary = await narrator.narrate(activity)
        await store.record(AlarmActivityEntry(activity: activity, summary: summary))
    }
}

/// A deterministic aggregate over recent wakes (WG-299) — the source of truth for the periodic full
/// summary. The narrator feeds these coarse counts to the model to phrase; on its own it produces the
/// fallback sentence. Counts only; no health/sleep inference or claim (#39).
struct AlarmActivitySummary: Sendable, Equatable {
    let total: Int
    let walked: Int
    let usedTap: Int
    let missed: Int
    let averageSteps: Int

    init(_ activities: [AlarmActivity]) {
        total = activities.count
        walked = activities.filter { $0.outcome == .walkedAndPassed }.count
        usedTap = activities.filter { $0.outcome == .tapAlternative }.count
        missed = activities.filter { $0.outcome == .timedOut || $0.outcome == .interrupted }.count
        let stepCounts = activities.filter { $0.walkRequired }.map(\.stepsWalked)
        averageSteps = stepCounts.isEmpty ? 0 : stepCounts.reduce(0, +) / stepCounts.count
    }

    var factors: [ExplanationFactor] {
        [
            ExplanationFactor(id: "wakes", value: "\(total)"),
            ExplanationFactor(id: "walked_off", value: "\(walked)"),
            ExplanationFactor(id: "used_tap", value: "\(usedTap)"),
            ExplanationFactor(id: "stayed_on", value: "\(missed)"),
            ExplanationFactor(id: "average_steps", value: "\(averageSteps)"),
        ]
    }

    var plainSummary: String {
        guard total > 0 else { return "No wakes recorded yet." }
        return "Across \(total) recent \(total == 1 ? "wake" : "wakes"), you walked the alarm off "
            + "\(walked) \(walked == 1 ? "time" : "times"), used the tap alternative \(usedTap), and "
            + "the alarm stayed on \(missed). Average \(averageSteps) steps per walk."
    }
}
