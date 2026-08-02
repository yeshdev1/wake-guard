import Foundation

/// Stable identity for an `Alarm`. A typed wrapper so an alarm id can't be
/// confused with any other UUID-keyed identifier.
struct AlarmID: Codable, Sendable, Equatable, Hashable {
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

/// A user-defined alarm: its schedule, travel and criticality policies, sound,
/// and snooze/challenge/pre-alarm policies, plus identity and revision metadata.
///
/// A value type built from already-validated components; its own initializer
/// enforces the cross-field invariants (`revision >= 0`, `updatedAt >=
/// createdAt`), and `Decodable` re-validates, so an invalid `Alarm` cannot be
/// constructed or decoded. Monotonic revision advancement and timestamp updates
/// on mutation are the command processor's job (WG-027).
struct Alarm: Identifiable, Codable, Sendable, Equatable, Hashable {
    let id: AlarmID
    var label: String
    var isEnabled: Bool
    var schedule: ScheduleRule
    var travelBehavior: TravelBehavior
    var criticality: Criticality
    var sound: AlarmSound
    var snoozePolicy: SnoozePolicy
    var challengePolicy: ChallengePolicy
    var preAlarmPolicy: PreAlarmPolicy
    let createdAt: Date
    var updatedAt: Date
    var revision: Int

    init(
        id: AlarmID,
        label: String,
        isEnabled: Bool = true,
        schedule: ScheduleRule,
        travelBehavior: TravelBehavior = .followLocal,
        criticality: Criticality = .standard,
        sound: AlarmSound = .default,
        snoozePolicy: SnoozePolicy = .disabled,
        challengePolicy: ChallengePolicy = .none,
        preAlarmPolicy: PreAlarmPolicy = .disabled,
        createdAt: Date,
        updatedAt: Date,
        revision: Int = 0
    ) throws {
        guard revision >= 0 else {
            throw DomainError.invalidAlarm(reason: "revision must be >= 0")
        }
        guard updatedAt >= createdAt else {
            throw DomainError.invalidAlarm(reason: "updatedAt must be >= createdAt")
        }
        self.id = id
        self.label = label
        self.isEnabled = isEnabled
        self.schedule = schedule
        self.travelBehavior = travelBehavior
        self.criticality = criticality
        self.sound = sound
        self.snoozePolicy = snoozePolicy
        self.challengePolicy = challengePolicy
        self.preAlarmPolicy = preAlarmPolicy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, isEnabled, schedule, travelBehavior, criticality, sound
        case snoozePolicy, challengePolicy, preAlarmPolicy, createdAt, updatedAt, revision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(AlarmID.self, forKey: .id),
            label: container.decode(String.self, forKey: .label),
            isEnabled: container.decode(Bool.self, forKey: .isEnabled),
            schedule: container.decode(ScheduleRule.self, forKey: .schedule),
            travelBehavior: container.decode(TravelBehavior.self, forKey: .travelBehavior),
            criticality: container.decode(Criticality.self, forKey: .criticality),
            sound: container.decode(AlarmSound.self, forKey: .sound),
            snoozePolicy: container.decode(SnoozePolicy.self, forKey: .snoozePolicy),
            challengePolicy: container.decode(ChallengePolicy.self, forKey: .challengePolicy),
            preAlarmPolicy: container.decode(PreAlarmPolicy.self, forKey: .preAlarmPolicy),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            updatedAt: container.decode(Date.self, forKey: .updatedAt),
            revision: container.decode(Int.self, forKey: .revision))
    }
}
