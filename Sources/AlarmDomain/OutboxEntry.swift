import Foundation

/// Lifecycle of a queued external operation (ARCHITECTURE §6). `applied` and
/// `failed` are terminal; `pending` / `inProgress` / `uncertain` are non-terminal
/// and must be recovered by launch-time reconciliation (WG-016/WG-029). A
/// string-raw enum, so an unknown status fails to decode (#27).
enum OutboxStatus: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Enqueued, not yet attempted.
    case pending
    /// Mid-call to the external system.
    case inProgress
    /// The external operation completed successfully.
    case applied
    /// Attempted, but the outcome is unknown (crash/timeout) — needs
    /// reconciling (#10; ARCHITECTURE §6: never assume a cancellation means the
    /// operation did not occur).
    case uncertain
    /// Known to have failed.
    case failed

    /// Whether the entry has reached a terminal state and needs no further work.
    var isTerminal: Bool { self == .applied || self == .failed }
}

/// Stable identity for an `OutboxEntry`.
struct OutboxEntryID: Codable, Sendable, Equatable, Hashable {
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

/// A pending external (AlarmKit) operation persisted in the outbox so a command
/// applied locally is eventually reconciled to the system even across crashes
/// (ARCHITECTURE §5–§6). Carries an `idempotencyKey` so a retried operation is
/// applied at most once. The transition mechanics (enqueue → in-progress →
/// completed/failed, retry, reconciliation) are WG-016; this type only records
/// the state.
struct OutboxEntry: Identifiable, Codable, Sendable, Equatable, Hashable {
    let id: OutboxEntryID
    let command: AlarmCommand
    let idempotencyKey: String
    var status: OutboxStatus
    let createdAt: Date
    var attempts: Int
    /// A coarse, user-safe failure reason — never raw error text that could embed
    /// a label/location/etc. (#41). The retry cap is WG-016 (no unbounded retries).
    var lastFailureReason: String?

    /// The alarm the queued command targets.
    var alarmID: AlarmID { command.alarmID }
}
