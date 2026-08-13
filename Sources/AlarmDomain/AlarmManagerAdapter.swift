import Foundation

/// The boundary to the system alarm authority (AlarmKit). Per SAFETY_INVARIANTS #1
/// the concrete adapter is the **only** component that calls AlarmKit, and per #2
/// only `AlarmCommandProcessor` (WG-027) may invoke it. This is a domain-owned port
/// (like `Repositories`): it references only Foundation and domain types, so the
/// domain stays framework-independent — the real AlarmKit-backed adapter lives in
/// `AlarmInfrastructure`, and tests/previews use `FakeAlarmManagerAdapter`.
///
/// Occurrence times are computed by the pure scheduling engine and passed in; the
/// adapter never computes schedules. Every mutating call either succeeds (applied),
/// throws a definite `AlarmManagerError`, or throws `.uncertain` — the last means
/// the outcome is unknown and the caller must reconcile, never assume it did not
/// happen (#10; maps to the outbox's `.uncertain`).
///
/// A *cancelled* mutating call (Swift task cancellation) must likewise be treated by
/// the caller as `.uncertain` — the operation may already have applied; the adapter
/// does not roll back on cancellation (ARCHITECTURE §6).
protocol AlarmManagerAdapter: Sendable {
    /// The current authorization to schedule system alarms. Never throws — an
    /// undetermined/denied state is a value, not an error.
    func authorizationState() async -> AlarmAuthorizationState

    /// Requests authorization if undetermined and returns the resulting state. The
    /// full prompt/denial policy is WG-025; this is the primitive it builds on.
    func requestAuthorization() async throws -> AlarmAuthorizationState

    /// Schedule (or reschedule) the alarm in the system authority. Idempotent on
    /// `alarmID`: scheduling an already-scheduled id replaces its occurrence. The
    /// real adapter (WG-026) must uphold this idempotency via a *persisted* `AlarmID`
    /// ↔ system-id mapping — losing that mapping risks a duplicate alarm.
    func schedule(_ request: AlarmScheduleRequest) async throws

    /// Cancel the *scheduled (future)* alarm with this id. Cancelling an unknown id is
    /// a no-op (already absent), not an error. This is **not** how a currently
    /// *ringing* alarm is stopped — stopping a ring is gated on a valid challenge pass
    /// (#24) and is a separate primitive added with the challenge state machine
    /// (WG-073); a reconciler repairing an "extra" system alarm must never cancel one
    /// that is currently firing.
    func cancel(alarmID: AlarmID) async throws

    /// Stop the currently *ringing* alarm with this id — the authorized ring-stop, gated on a valid
    /// challenge pass (#24, WG-073). Stopping an id that is **not** ringing is a **no-op**
    /// (idempotent), so a racing / duplicate pass callback can neither error nor double-stop.
    /// Distinct from `cancel(alarmID:)`: that removes a *scheduled future* alarm (and must never stop
    /// a ring), while this stops the *current* alert and leaves the alarm's next occurrence intact.
    /// Only `AlarmCommandProcessor` invokes it (#2), and only after a valid pass. Same
    /// uncertain / cancellation contract as the other mutating calls.
    func stopRing(alarmID: AlarmID) async throws

    /// Snooze the alarm so it next fires at `until` (the caller derives `until` from
    /// the snooze policy; the adapter applies no policy). Snoozing an id the system
    /// does not hold is a no-op — there is no occurrence to defer.
    func snooze(alarmID: AlarmID, until: Date) async throws

    /// The alarms currently scheduled in the system authority — the ground truth for
    /// launch/foreground reconciliation and divergence detection (WG-029). Each
    /// snapshot carries `isCritical`, so the reconciler can detect a criticality drift
    /// (a critical alarm silently downgraded), not only presence/time divergence.
    func scheduledAlarms() async throws -> [ScheduledAlarmSnapshot]
}

/// Authorization to schedule system alarms. A string-raw enum so an unknown value
/// fails to decode rather than being silently admitted (#27).
enum AlarmAuthorizationState: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case notDetermined
    case authorized
    case denied
    /// Policy / parental controls forbid scheduling — unlike `.denied`, a Settings
    /// deep link cannot fix it, so the caller falls back to a non-AlarmKit path while
    /// preserving the last safe alarm (#10). WG-025 handles the recovery flow.
    case restricted
}

/// A domain-neutral request to schedule one alarm occurrence — no AlarmKit types
/// leak into the domain. Carries the id, the precomputed `fireTime`, the display
/// `title`, and `isCritical`. Sound and recurrence are intentionally *not* here: the
/// scheduling engine re-drives recurrence per occurrence, and mapping `Alarm.sound`
/// to the system layer is deferred to the real adapter (WG-026, which sees the
/// AlarmKit API) — that mapping must not silently drop the user's chosen sound.
struct AlarmScheduleRequest: Sendable, Equatable, Hashable {
    let alarmID: AlarmID
    /// The absolute instant the alarm should fire (computed by the scheduling engine).
    let fireTime: Date
    /// User-facing title the system alarm shows (the alarm's label).
    let title: String
    /// Critical alarms present with heightened urgency and must ring through silent/
    /// focus modes. The policy engine — not the model — assigns criticality (#31).
    let isCritical: Bool
    /// The walk challenge's required step count, or nil when the alarm has no walk challenge. When set, the
    /// scheduled system alarm offers a "Start walk" action that opens the app to the challenge (WG-281/282).
    let requiredSteps: Int?
    /// For a wake-chain member (WG-291): the alarm this re-ring belongs to. The "Start walk" intent routes
    /// to the **parent's** challenge, and reconciliation re-validates the member against the parent's
    /// current chain. Nil for a main occurrence.
    var parentAlarmID: AlarmID?

    init(
        alarmID: AlarmID, fireTime: Date, title: String, isCritical: Bool, requiredSteps: Int? = nil
    ) {
        self.alarmID = alarmID
        self.fireTime = fireTime
        self.title = title
        self.isCritical = isCritical
        self.requiredSteps = requiredSteps
    }

    /// Build the request for an alarm's computed occurrence — the single place that maps criticality + the
    /// walk-challenge step count into the system request (WG-281).
    init(alarm: Alarm, fireTime: Date) {
        self.init(
            alarmID: alarm.id, fireTime: fireTime, title: alarm.label,
            isCritical: alarm.criticality == .critical,
            requiredSteps: alarm.challengePolicy.requiredSteps)
    }
}

/// A read-back of one alarm scheduled in the system authority, for reconciliation.
/// Carries `isCritical` so the reconciler can compare *content* (a critical alarm
/// must not have silently become non-critical), not only presence and time.
struct ScheduledAlarmSnapshot: Sendable, Equatable, Hashable {
    let alarmID: AlarmID
    let fireTime: Date
    let isCritical: Bool
}

/// Typed failures from the adapter.
enum AlarmManagerError: Error, Equatable, Sendable {
    /// The operation was attempted but its outcome is unknown (timeout / interruption
    /// / crash mid-call). The caller must reconcile against the system — never assume
    /// it did not occur (#10; maps to the outbox's `.uncertain`).
    case uncertain
    /// Not authorized to schedule system alarms.
    case notAuthorized
    /// The system alarm service is unavailable in this state.
    case unavailable
    /// A definite failure. `reason` is a coarse, user-safe string — never raw error
    /// text that could embed sensitive data (#41).
    case failed(reason: String)
}
