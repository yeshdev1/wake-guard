import Foundation

/// Whether waking requires a verified challenge, and how. `.none` has no
/// challenge; `.walk` carries validated walk parameters and — crucially — always
/// an `accessibleFallback`, so SCOPE §2.3 ("accessible alternative always
/// available") holds by construction whenever a challenge is required.
enum ChallengePolicy: Codable, Sendable, Equatable, Hashable {
    case none
    case walk(WalkChallenge)

    var isRequired: Bool {
        switch self {
        case .none: false
        case .walk: true
        }
    }

    /// The always-available accessible alternative when a challenge is required.
    var accessibleFallback: AccessibleChallenge? {
        switch self {
        case .none: nil
        case .walk(let challenge): challenge.accessibleFallback
        }
    }
}

/// Validated parameters for the ten-second walk challenge. Non-positive
/// durations/steps/cadence are unrepresentable.
struct WalkChallenge: Codable, Sendable, Equatable, Hashable {
    let targetDuration: TimeInterval
    let minimumSteps: Int
    /// Plausibility cap on cadence (steps per second); shaking exceeds it.
    let maximumCadence: Double
    let allowedPauses: Int
    let antiCheatThreshold: Double
    let accessibleFallback: AccessibleChallenge
    let calibrationProfileID: CalibrationProfileID?

    init(
        targetDuration: TimeInterval,
        minimumSteps: Int,
        maximumCadence: Double,
        allowedPauses: Int,
        antiCheatThreshold: Double,
        accessibleFallback: AccessibleChallenge,
        calibrationProfileID: CalibrationProfileID? = nil
    ) throws {
        guard targetDuration > 0 else {
            throw DomainError.invalidWalkChallenge(reason: "targetDuration must be > 0")
        }
        guard minimumSteps >= 1 else {
            throw DomainError.invalidWalkChallenge(reason: "minimumSteps must be >= 1")
        }
        guard maximumCadence > 0 else {
            throw DomainError.invalidWalkChallenge(reason: "maximumCadence must be > 0")
        }
        guard allowedPauses >= 0 else {
            throw DomainError.invalidWalkChallenge(reason: "allowedPauses must be >= 0")
        }
        guard antiCheatThreshold >= 0 else {
            throw DomainError.invalidWalkChallenge(reason: "antiCheatThreshold must be >= 0")
        }
        self.targetDuration = targetDuration
        self.minimumSteps = minimumSteps
        self.maximumCadence = maximumCadence
        self.allowedPauses = allowedPauses
        self.antiCheatThreshold = antiCheatThreshold
        self.accessibleFallback = accessibleFallback
        self.calibrationProfileID = calibrationProfileID
    }

    private enum CodingKeys: String, CodingKey {
        case targetDuration, minimumSteps, maximumCadence, allowedPauses
        case antiCheatThreshold, accessibleFallback, calibrationProfileID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            targetDuration: container.decode(TimeInterval.self, forKey: .targetDuration),
            minimumSteps: container.decode(Int.self, forKey: .minimumSteps),
            maximumCadence: container.decode(Double.self, forKey: .maximumCadence),
            allowedPauses: container.decode(Int.self, forKey: .allowedPauses),
            antiCheatThreshold: container.decode(Double.self, forKey: .antiCheatThreshold),
            accessibleFallback: container.decode(
                AccessibleChallenge.self, forKey: .accessibleFallback),
            calibrationProfileID: container.decodeIfPresent(
                CalibrationProfileID.self, forKey: .calibrationProfileID))
    }
}

/// A non-motion alternative to the walk challenge (detail in WG-072).
enum AccessibleChallenge: Codable, Sendable, Equatable, Hashable {
    case tapSequence
    case pressAndHold
}

/// Reference to a stored motion calibration profile (built in WG-075).
struct CalibrationProfileID: Codable, Sendable, Equatable, Hashable {
    let rawValue: UUID

    init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
