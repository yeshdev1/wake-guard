/// Persistence ports for the domain (WG-012). These protocols reference only
/// domain types and Foundation primitives — **no Apple persistence framework
/// (Core Data / SwiftData) type ever appears here**, so the domain stays
/// framework-independent (ARCHITECTURE §1/§5). Implementations are WG-013–016.
/// Methods are `async throws` because the backing store is asynchronous.

/// Reads and writes `Alarm` aggregates.
protocol AlarmRepository: Sendable {
    /// Insert a new alarm or replace the existing one with the same id. The
    /// implementation must honor optimistic concurrency on `Alarm.revision` — a
    /// stale-revision save must not silently overwrite a newer one (WG-014).
    func save(_ alarm: Alarm) async throws
    func alarm(id: AlarmID) async throws -> Alarm?
    func allAlarms() async throws -> [Alarm]
    func deleteAlarm(id: AlarmID) async throws
}

/// Append-only audit trail (SAFETY_INVARIANTS #46–#49). The protocol deliberately
/// exposes **no update or delete** — an audit event, once appended, cannot be
/// mutated or removed through this port (#48). Reads are for the
/// user-understandable history (#49).
protocol AuditRepository: Sendable {
    func append(_ event: AuditEvent) async throws
    func events(forAlarm id: AlarmID) async throws -> [AuditEvent]
    func allEvents() async throws -> [AuditEvent]
}

/// Loads and stores app feature-flag/kill-switch settings.
protocol SettingsRepository: Sendable {
    /// The current settings, or `AppSettings.default` if none is stored.
    func settings() async throws -> AppSettings
    func save(_ settings: AppSettings) async throws
}

/// The outbox of pending external (AlarmKit) operations (ARCHITECTURE §5–§6).
/// Entries move pending → inProgress → applied/uncertain/failed; the mechanics
/// (retry, idempotency dedup, launch-time reconciliation) are WG-016.
protocol OutboxRepository: Sendable {
    /// Enqueue a pending operation. The implementation must be idempotent on
    /// `entry.idempotencyKey` — a retried operation is applied at most once (WG-016).
    func enqueue(_ entry: OutboxEntry) async throws
    func entry(id: OutboxEntryID) async throws -> OutboxEntry?
    /// Look up by idempotency key, so a duplicate operation can be detected.
    func entry(idempotencyKey: String) async throws -> OutboxEntry?
    /// Freshly-pending entries (work to attempt).
    func pendingEntries() async throws -> [OutboxEntry]
    /// All non-terminal entries (`pending` / `inProgress` / `uncertain`) — what
    /// launch reconciliation must recover, so a stranded operation is never lost
    /// (#10); not just the freshly-pending ones.
    func unresolvedEntries() async throws -> [OutboxEntry]
    func markInProgress(_ id: OutboxEntryID) async throws
    func markApplied(_ id: OutboxEntryID) async throws
    /// The external op was attempted but its outcome is unknown; reconciliation
    /// will resolve it (ARCHITECTURE §6).
    func markUncertain(_ id: OutboxEntryID) async throws
    /// `reason` must be a coarse, user-safe string — never raw error text that
    /// could embed sensitive data (#41). The retry cap is WG-016.
    func markFailed(_ id: OutboxEntryID, reason: String) async throws
}
