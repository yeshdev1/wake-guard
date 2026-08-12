import Foundation

/// The desired-vs-actual reconciliation planner (WG-029; ARCHITECTURE §127
/// "AlarmReconciler"). A **pure** function over the persisted alarms and a snapshot of
/// the system authority: it detects the three ways they diverge —
///
/// - **missing:** an enabled alarm whose next occurrence should be scheduled, but the
///   system does not hold it;
/// - **extra:** a system alarm with no corresponding *enabled* local alarm (the alarm
///   was disabled or deleted), which the system must let go;
/// - **divergent:** a system alarm whose fire time or criticality no longer matches the
///   alarm's desired next occurrence (a schedule edit, a DST shift, or a critical alarm
///   silently downgraded — #16).
///
/// It performs no I/O and holds no state, so it is deterministic and fully testable; the
/// `AlarmCommandProcessor` reads ground truth and applies the plan, because only the
/// processor may invoke the adapter (#2). The plan is **idempotent**: once the system
/// matches the desired occurrences it is empty, so re-running reconciliation repairs
/// nothing (a safe repair never oscillates).
struct AlarmReconciler: Sendable {
    private let engine = AlarmSchedulingEngine()

    func plan(
        desired alarms: [Alarm], system: [ScheduledAlarmSnapshot], now: Date,
        deviceTimeZone: TimeZone
    ) -> [ReconciliationRepair] {
        // The desired system state: each *enabled* alarm's next occurrence. A disabled
        // alarm — or one with no upcoming occurrence — is intentionally absent, so any
        // system alarm standing in for it is "extra" and gets cancelled.
        var desiredByID: [AlarmID: AlarmScheduleRequest] = [:]
        for alarm in alarms where alarm.isEnabled {
            guard
                let occurrence = engine.nextOccurrence(
                    for: alarm, after: now, deviceTimeZone: deviceTimeZone)
            else { continue }
            desiredByID[alarm.id] = AlarmScheduleRequest(alarm: alarm, fireTime: occurrence)
        }

        var systemByID: [AlarmID: ScheduledAlarmSnapshot] = [:]
        for snapshot in system { systemByID[snapshot.alarmID] = snapshot }

        var repairs: [ReconciliationRepair] = []
        // Missing or divergent → (re)schedule to the desired occurrence.
        for (id, request) in desiredByID {
            if let held = systemByID[id], held.fireTime == request.fireTime,
                held.isCritical == request.isCritical
            {
                continue  // already matches — no repair (idempotent).
            }
            repairs.append(.schedule(request))
        }
        // Extra → a system alarm with no desired counterpart.
        for snapshot in system where desiredByID[snapshot.alarmID] == nil {
            repairs.append(.cancel(snapshot.alarmID))
        }
        // Dictionary iteration is unordered; sort by target id so the plan (and the
        // audit events it produces) is deterministic.
        return repairs.sorted {
            $0.alarmID.rawValue.uuidString < $1.alarmID.rawValue.uuidString
        }
    }
}

/// A single safe repair the reconciler proposes; the processor applies it against the
/// system authority (#2). Both are idempotent at the adapter: `schedule` replaces an
/// occurrence, and `cancel` of an absent id is a no-op.
enum ReconciliationRepair: Sendable, Equatable {
    /// (Re)schedule a missing or divergent alarm to its desired next occurrence.
    case schedule(AlarmScheduleRequest)
    /// Cancel an extra system alarm that no longer matches any enabled local alarm.
    /// `cancel` is future-only, so this never stops a currently *ringing* alarm — that
    /// is gated on a valid challenge pass (#24).
    case cancel(AlarmID)

    /// The alarm this repair targets.
    var alarmID: AlarmID {
        switch self {
        case .schedule(let request): request.alarmID
        case .cancel(let id): id
        }
    }
}

/// The result of a reconciliation pass (WG-029): how many system alarms were
/// (re)scheduled, cancelled, left `uncertain` (adapter outcome unknown — re-checked on
/// the next pass, not a hard failure), or failed to repair. `stale` counts repairs that
/// were re-validated against current desired state at apply time and dropped because a
/// concurrent command had already changed the alarm (the lost-update guard, WG-244) —
/// not an error, the current intent is already correct. `skipped` means ground truth or
/// the desired state could not be read, so **nothing** was repaired (fail-safe, #10) —
/// the last known safe schedule is preserved and the next pass retries.
struct ReconciliationSummary: Sendable, Equatable {
    var scheduled = 0
    var cancelled = 0
    var failed = 0
    var uncertain = 0
    var stale = 0
    var skipped = false
}
