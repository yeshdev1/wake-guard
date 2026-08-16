import Foundation

/// How a rung alarm's wake challenge ended (WG-299) — the deterministic outcome recorded for the activity
/// history. A closed set so a stored value always decodes to a known case (#27); an unknown raw value
/// decodes to `.interrupted` (the safe "we couldn't confirm a clean wake" reading).
enum AlarmActivityOutcome: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// The user completed the walk and the alarm turned off.
    case walkedAndPassed
    /// The user turned it off with the accessible tap alternative (#22) instead of walking.
    case tapAlternative
    /// The walk didn't complete within the window.
    case timedOut
    /// The attempt was interrupted (sensors unavailable / failed) — the alarm stayed active.
    case interrupted

    init(fromStored raw: String) {
        self = AlarmActivityOutcome(rawValue: raw) ?? .interrupted
    }
}

/// One recorded wake — the deterministic facts about a rung alarm's challenge (WG-299). This is the
/// **source of truth**; any AI phrasing narrates *these* facts and may never add to them (#32). It holds
/// no label, schedule, health, or location value — only interaction facts (#41) — and is stored on-device
/// only (#35/#40). `durationSeconds` is the time from the challenge starting to its outcome.
struct AlarmActivity: Sendable, Equatable, Hashable {
    let alarmID: AlarmID
    let occurredAt: Date
    let outcome: AlarmActivityOutcome
    let walkRequired: Bool
    let stepsWalked: Int
    let requiredSteps: Int
    let durationSeconds: Int

    /// A deterministic, plain-English one-liner — the **always-available** narration (the AI layer only
    /// rephrases this; if the model is unavailable this is what's shown, #33). Grounded entirely in the
    /// recorded facts, never a judgement or a health claim (#39).
    var plainSummary: String {
        switch outcome {
        case .walkedAndPassed:
            return "You walked \(stepsWalked) "
                + (stepsWalked == 1 ? "step" : "steps") + " in \(durationSeconds)s and the alarm "
                + "turned off."
        case .tapAlternative:
            return "You turned the alarm off with the tap alternative instead of walking."
        case .timedOut:
            return "The walk didn't finish in time — you reached \(stepsWalked) of "
                + "\(requiredSteps) steps, and the alarm stayed on."
        case .interrupted:
            return "The wake check was interrupted, so the alarm stayed on."
        }
    }
}
