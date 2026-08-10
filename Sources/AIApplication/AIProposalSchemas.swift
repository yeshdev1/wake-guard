import Foundation

/// A coarse sleep-quality band from journal extraction (WG-161). String-raw with a **fail-closed** decode
/// — an unrecognized value maps to `.unknown` (#27), never a fabricated band.
enum AISleepQualityBand: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case poor, fair, good, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AISleepQualityBand(rawValue: raw) ?? .unknown
    }
}

/// A challenge-difficulty preference (WG-161). Fail-closed to `.unknown` on an unrecognized value (#27).
enum AIChallengeDifficulty: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case easy, standard, hard, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AIChallengeDifficulty(rawValue: raw) ?? .unknown
    }
}

/// A **tomorrow-plan** proposal (WG-161) — a suggested wake time + the factor IDs it is grounded in. The
/// deterministic latest-safe-wake (WG-145) remains the source of truth; this is the model's advisory
/// framing. Bounds checked by `validate()`.
struct AITomorrowPlanProposal: Sendable, Equatable, Hashable, Codable {
    let suggestedWakeHour: Int
    let suggestedWakeMinute: Int
    /// The recorded-factor IDs this suggestion is grounded in (#32).
    let groundedFactorIDs: [String]
    let rationale: String

    func validate() throws {
        guard (0...23).contains(suggestedWakeHour) else {
            throw AISchemaError.outOfRange(field: "suggestedWakeHour")
        }
        guard (0...59).contains(suggestedWakeMinute) else {
            throw AISchemaError.outOfRange(field: "suggestedWakeMinute")
        }
    }
}

/// An **explanation** draft (WG-161) — free text plus the recorded-factor IDs it must be grounded in
/// (#32). The generator (WG-169) rejects any statement not tied to a known factor ID.
struct AIExplanationDraft: Sendable, Equatable, Hashable, Codable {
    let factorIDs: [String]
    let text: String
}

/// **Journal extraction** (WG-161) — structured fields pulled from a free-text sleep journal. Times are
/// minutes-past-midnight (`0..<1440`), checked by `validate()`; all fields optional (a journal may say
/// little).
struct AIJournalExtraction: Sendable, Equatable, Hashable, Codable {
    let bedtimeMinutesOfDay: Int?
    let wakeMinutesOfDay: Int?
    let quality: AISleepQualityBand
    let note: String?

    func validate() throws {
        if let bedtime = bedtimeMinutesOfDay {
            guard (0..<1_440).contains(bedtime) else {
                throw AISchemaError.outOfRange(field: "bedtime")
            }
        }
        if let wake = wakeMinutesOfDay {
            guard (0..<1_440).contains(wake) else { throw AISchemaError.outOfRange(field: "wake") }
        }
    }
}

/// A **policy preference** (WG-161) — the model's interpretation of a user preference into explicit,
/// bounded policy fields. Each is optional (`nil` = no opinion); the policy engine (never the model)
/// applies them, and none can set criticality (#31).
struct AIPolicyPreference: Sendable, Equatable, Hashable, Codable {
    let snoozeEnabled: Bool?
    let challengeDifficulty: AIChallengeDifficulty?
}
