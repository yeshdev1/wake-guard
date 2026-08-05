import AlarmKit
import Foundation

/// Maps a WakeGuard domain schedule to AlarmKit's `Alarm.Schedule` (WG-026), and a
/// domain `AlarmID` to its AlarmKit identifier. Pure and testable — it constructs
/// AlarmKit value types without touching `AlarmManager`.
///
/// **Per-occurrence, not native recurrence.** Every schedule maps to `.fixed(instant)`
/// at the next occurrence computed by the pure `AlarmSchedulingEngine`, so scheduling
/// authority stays in the engine (#13): tz, DST, and — via the *injected* `timeZone`
/// the caller resolves from `TravelBehavior` (WG-021) — fixed-zone vs follow-device
/// (#12/#16) are all decided by the domain, and AlarmKit is handed a resolved instant,
/// never a rule to re-derive. Recurrence is re-driven by the app (schedule-ahead +
/// launch/foreground reconciliation, WG-027/WG-029). AlarmKit's own `.relative`
/// recurrence was deliberately rejected — it would cede tz/DST resolution to AlarmKit
/// and cannot express a fixed-zone weekly alarm (see DECISIONS WG-026).
///
/// **Correlation is by identity:** AlarmKit's `Alarm.ID` is a `UUID` the caller
/// supplies, so `AlarmID.rawValue` *is* the AlarmKit id — no separate mapping to
/// persist.
struct AlarmKitScheduleMapper: Sendable {
    /// The domain also defines `Alarm`, so `AlarmKit.Alarm.Schedule` must be qualified;
    /// this alias keeps that explicit and a bare `Alarm` conspicuous in review.
    private typealias KitSchedule = AlarmKit.Alarm.Schedule

    private let engine = AlarmSchedulingEngine()

    /// The AlarmKit identifier for a domain alarm — identity, so the scheduled system
    /// alarm and its local alarm share one UUID. (`AlarmKit.Alarm.ID` is a `UUID`.)
    func alarmKitID(for id: AlarmID) -> UUID {
        id.rawValue
    }

    /// The AlarmKit schedule for `rule`'s next occurrence strictly after `now`, in the
    /// caller-resolved `timeZone`, or `nil` if there is no next occurrence (a past
    /// one-time alarm). Both supported schedule types map through this one path:
    /// `.oneTime` and `.weekly` each resolve to a `.fixed` instant via the engine.
    func schedule(
        for rule: ScheduleRule, after now: Date, in timeZone: TimeZone
    ) -> AlarmKit.Alarm.Schedule? {
        engine.nextOccurrence(of: rule, after: now, in: timeZone)
            .map { KitSchedule.fixed($0) }
    }
}
