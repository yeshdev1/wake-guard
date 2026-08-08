import Foundation

/// An interim `AlarmManagerAdapter` that performs **no AlarmKit calls** (WG-042). It is
/// composed into the live graph so the create/edit flows work — the command processor still
/// persists every alarm locally (the source of truth, #10) and audits it — while the real
/// `SystemAlarmManagerAdapter`, the authorization-prompt UI, the `NSAlarmKitUsageDescription`
/// entitlement, and on-device verification land together as a cohesive follow-on
/// (WG-025 UI / WG-030). Until then no alarm is placed in the system authority, so an alarm
/// is created and shown in the list but does **not** ring yet — this is deliberate and
/// documented (DECISIONS WG-042).
///
/// A scheduling attempt reports **`.uncertain`**, not a failure: the alarm is saved and its
/// system-schedule state is simply unknown/deferred, so the outbox leaves it for
/// reconciliation to place once a real adapter is wired — never a user-facing "couldn't
/// create" error for what is only a deferred sync.
struct DeferredAlarmManagerAdapter: AlarmManagerAdapter {
    func authorizationState() async -> AlarmAuthorizationState { .notDetermined }

    func requestAuthorization() async throws -> AlarmAuthorizationState { .notDetermined }

    func schedule(_ request: AlarmScheduleRequest) async throws {
        throw AlarmManagerError.uncertain
    }

    func cancel(alarmID: AlarmID) async throws {
        // Nothing is scheduled in the system, so there is nothing to cancel — a no-op.
    }

    func stopRing(alarmID: AlarmID) async throws {
        // This interim adapter makes no AlarmKit calls, so no alarm rings yet — there is nothing to
        // stop, a no-op. The real ring-stop lands with the AlarmKit-backed adapter (WG-026).
    }

    func snooze(alarmID: AlarmID, until: Date) async throws {
        // Nothing is scheduled, so there is nothing to defer — `.unavailable`, not
        // `.uncertain` (which would send reconciliation chasing a phantom snooze).
        throw AlarmManagerError.unavailable
    }

    func scheduledAlarms() async throws -> [ScheduledAlarmSnapshot] { [] }
}
