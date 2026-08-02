import Foundation

/// Who caused an alarm mutation (SAFETY_INVARIANTS #46). A string-raw enum, so
/// decoding an unknown or forged actor throws rather than silently admitting it
/// (#27 — reject unknown enum values). Named `AuditActor` to avoid overloading
/// the concurrency `Actor` marker protocol.
enum AuditActor: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case user
    case systemReconciliation
    case approvedAgentProposal
    case migration
    case recovery
}

/// The mechanism a command originated from (SAFETY_INVARIANTS #47 "source").
/// Unknown values fail to decode.
enum CommandSource: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case userInterface
    case notificationAction
    case agentProposal
    case reconciliation
    case migration
    case recovery
}

/// The result of applying a command (SAFETY_INVARIANTS #47 "outcome").
enum Outcome: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case succeeded
    case failed
    case rejected
    case noOp
}

/// Correlates the events that make up a single logical operation.
struct CorrelationID: Codable, Sendable, Equatable, Hashable {
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

/// Stable identity for an `AuditEvent`.
struct AuditEventID: Codable, Sendable, Equatable, Hashable {
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

/// An immutable record of a single alarm mutation (SAFETY_INVARIANTS #46–#50):
/// who (`actor`), what (`command`, whose `alarmID` names the target), the
/// before/after state hashes, when, from where (`source`), the `outcome`, a
/// `correlationID`, and a user-visible reason. All fields are `let`; append-only
/// *storage* is the audit repository's job (WG-015). Recovery is distinguishable
/// from ordinary edits via `isRecovery` (#50). Hashes are computed by the command
/// processor (WG-027); this type only records them.
struct AuditEvent: Identifiable, Codable, Sendable, Equatable, Hashable {
    let id: AuditEventID
    let actor: AuditActor
    let command: AlarmCommand
    /// State hashes bracketing the mutation. `nil` is legal only where no such
    /// state exists — `oldStateHash` for a `create`, `newStateHash` for a delete.
    /// A *succeeded mutation* must carry both; the command processor (WG-027)
    /// enforces that, since the model cannot know which commands mutate state.
    let oldStateHash: String?
    let newStateHash: String?
    let timestamp: Date
    let source: CommandSource
    let outcome: Outcome
    let correlationID: CorrelationID
    let userVisibleReason: String

    /// The alarm the recorded command targets.
    var alarmID: AlarmID { command.alarmID }

    /// Recovery actions are distinguishable from ordinary edits (#50).
    var isRecovery: Bool {
        actor == .recovery || source == .recovery
    }
}
