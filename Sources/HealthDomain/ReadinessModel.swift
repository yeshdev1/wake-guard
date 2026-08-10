import Foundation

/// A single transparent input to the readiness estimate (WG-125). Each factor derives from sleep data
/// (WG-123/124) via a documented formula and contributes a normalized `contribution` in `[0, 1]`
/// (1 = fully rested on that axis) at a fixed `weight`. **No black box** — the factors *are* the
/// explanation.
enum ReadinessFactorKind: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case sleepDuration
    case sleepConsistency
    case sleepDebt
}

/// One factor's deterministic contribution to the readiness estimate (WG-125).
struct ReadinessFactor: Sendable, Equatable, Hashable {
    let kind: ReadinessFactorKind
    /// Normalized `[0, 1]`, higher = more rested on this axis.
    let contribution: Double
    /// The factor's weight in the blend (fixed per kind).
    let weight: Double
}

/// How confident the estimate is, driven by **how many factors are present** — a **missing factor
/// reduces certainty** (WG-125), it never fabricates a value.
enum ReadinessCertainty: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case low
    case moderate
    case high
}

/// A neutral, qualitative readiness level (WG-125). Deliberately **not** a "score out of 100" — the
/// product avoids competitive/guilt-inducing sleep scores; WG-126 supplies gentle copy + disclaimers.
enum ReadinessLevel: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case low
    case moderate
    case good
}

/// The readiness estimate (WG-125): the deterministic factors, an overall certainty, and — computed from
/// the factors — a transparent weighted score and its qualitative level. Holds **no medical
/// authority**: it is an explainable estimate, **never a diagnosis** (#39). `level`/`weightedScore` are
/// `nil` when no factor is available (unavailable, not fabricated).
struct ReadinessAssessment: Sendable, Equatable {
    let factors: [ReadinessFactor]
    let certainty: ReadinessCertainty

    /// The weight-normalized blend of the **available** factors' contributions, `[0, 1]` — or `nil` when
    /// none are available. Re-normalizing by present weight means a missing factor lowers *certainty*, not
    /// the score (it doesn't drag readiness toward 0).
    var weightedScore: Double? {
        let totalWeight = factors.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        return factors.reduce(0) { $0 + $1.contribution * $1.weight } / totalWeight
    }

    /// The qualitative level from `weightedScore` via fixed thresholds (`>= 0.75` good, `>= 0.5` moderate,
    /// else low), or `nil` when unavailable. Deterministic.
    var level: ReadinessLevel? {
        guard let score = weightedScore else { return nil }
        if score >= 0.75 { return .good }
        if score >= 0.5 { return .moderate }
        return .low
    }
}

/// The inputs to the readiness estimate (WG-125) — each optional so a **missing** signal reduces
/// certainty rather than fabricating a value.
struct ReadinessInputs: Sendable, Equatable {
    let lastNightAsleep: TimeInterval?
    let consistency: SleepConsistency?
    let debt: SleepDebtEstimate?
    let need: SleepNeed
}

/// Builds the readiness estimate from sleep-derived inputs (WG-125). Pure and **deterministic** — each
/// factor's contribution is a documented, recomputable function; the overall estimate is a transparent
/// weighted blend. No black-box model, no diagnosis.
enum ReadinessModel {
    static let durationWeight = 0.5
    static let consistencyWeight = 0.25
    static let debtWeight = 0.25

    /// The deviation (minutes) at which the consistency contribution reaches 0.
    static let consistencyFloorMinutes = 120.0

    static func assess(_ inputs: ReadinessInputs) -> ReadinessAssessment {
        var factors: [ReadinessFactor] = []
        if let asleep = inputs.lastNightAsleep {
            factors.append(
                ReadinessFactor(
                    kind: .sleepDuration, contribution: durationScore(asleep, need: inputs.need),
                    weight: durationWeight))
        }
        if let consistency = inputs.consistency {
            factors.append(
                ReadinessFactor(
                    kind: .sleepConsistency, contribution: consistencyScore(consistency),
                    weight: consistencyWeight))
        }
        if let debt = inputs.debt {
            factors.append(
                ReadinessFactor(
                    kind: .sleepDebt, contribution: debtScore(debt), weight: debtWeight))
        }
        return ReadinessAssessment(factors: factors, certainty: certainty(available: factors.count))
    }

    /// Fraction of last night's need that was met, clamped `[0, 1]`.
    static func durationScore(_ asleep: TimeInterval, need: SleepNeed) -> Double {
        clamp(asleep / need.perNight)
    }

    /// 1 at a perfectly regular schedule, decaying linearly to 0 at `consistencyFloorMinutes` of
    /// night-to-night variation.
    static func consistencyScore(_ consistency: SleepConsistency) -> Double {
        clamp(1 - consistency.meanDeviationMinutes / consistencyFloorMinutes)
    }

    /// 1 at no debt, decaying linearly to 0 at three nights' worth of the assumed need.
    static func debtScore(_ debt: SleepDebtEstimate) -> Double {
        let floor = debt.sleepNeed * 3
        guard floor > 0 else { return 1 }
        return clamp(1 - debt.debt / floor)
    }

    /// More present factors → higher certainty; a missing factor reduces it.
    static func certainty(available: Int) -> ReadinessCertainty {
        switch available {
        case 0, 1: .low
        case 2: .moderate
        default: .high
        }
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}
