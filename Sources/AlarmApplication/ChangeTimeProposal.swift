import Foundation

/// A **proposed** new fire time for an existing alarm (WG-086) — the value the "Change time"
/// pre-alarm action opens for the user to review before saving. It is deliberately **inert**:
/// constructing it, previewing its next occurrence, and building its command all mutate *nothing*
/// (no persistence, no AlarmKit, not even a read). The original alarm therefore stays exactly as
/// scheduled — and keeps ringing on its ORIGINAL schedule — until the user explicitly saves and that
/// save actually succeeds (#7).
///
/// The only way a proposal changes anything is `command(now:)`, a normal `.update(Alarm)` submitted
/// through `AlarmCommandProcessor.process(_:)`, which authorizes it. So changing an imminent — or
/// critical — alarm is confirmation-gated by `DefaultAlarmPolicyEngine` (#6): the imminent ring is
/// never suppressed by opening or holding this proposal, and an unconfirmed save of an imminent /
/// critical alarm returns `.needsConfirmation`, mutating nothing.
///
/// Foundation-only (it composes domain values + the pure scheduling engine), holding no alarm
/// authority of its own — mirroring `AlarmProposal`: it merely *carries* a would-be command.
struct ChangeTimeProposal: Sendable, Equatable {
    /// The alarm the user is proposing to retime. Held **by value** and never mutated in place — a
    /// proposal is a snapshot; the live stored alarm is untouched until a save succeeds.
    let target: Alarm
    /// The proposed wall-clock time. Already range-validated (`TimeOfDay` is unrepresentable out of
    /// 00:00–23:59), so no invalid time can enter a proposal.
    let proposedTime: TimeOfDay
    /// For a one-time alarm, an optional new calendar date (retime to a different day). `nil` keeps
    /// the alarm's existing date. Ignored for a weekly alarm (its recurrence days are unchanged here
    /// — day-of-week edits are the full editor's job, not this focused retime).
    let proposedDate: CalendarDate?

    /// Build a proposal. **Pure and inert** — it validates nothing beyond the already-validated
    /// components it is handed and touches no side-effecting collaborator. `proposedDate` is only
    /// meaningful for a one-time alarm.
    init(target: Alarm, proposedTime: TimeOfDay, proposedDate: CalendarDate? = nil) {
        self.target = target
        self.proposedTime = proposedTime
        self.proposedDate = proposedDate
    }

    /// Whether the proposal actually changes the alarm's schedule. A no-op proposal (the proposed
    /// time/date equal the current ones) lets the caller skip an audit-noise `.update` and simply
    /// keep the original — still the safe outcome (#7).
    var isChange: Bool {
        target.schedule != retimedSchedule
    }

    /// The alarm the user *would* save — a copy of `target` with only its wall-clock time (and, for a
    /// one-time alarm, optionally its date) replaced, its `revision` bumped and `updatedAt` set to
    /// `now`. **Pure**: it constructs and returns a value; it persists nothing and rings nothing.
    ///
    /// Everything else is preserved deliberately: the **id** (so this updates, never duplicates), the
    /// enabled flag, the anchor IANA zone (never silently re-anchored to the device zone, #11/#16),
    /// criticality and every policy, and any turned-off occurrences. It re-throws only if the domain
    /// `Alarm` invariant rejected the copy (unreachable for a valid `target` + validated time) —
    /// surfaced as `nil` rather than a force-unwrap so a bad proposal can never crash or half-save.
    func proposedAlarm(now: Date) -> Alarm? {
        try? Alarm(
            id: target.id, label: target.label, isEnabled: target.isEnabled,
            schedule: retimedSchedule, skippedOccurrences: target.skippedOccurrences,
            travelBehavior: target.travelBehavior, criticality: target.criticality,
            sound: target.sound, snoozePolicy: target.snoozePolicy,
            challengePolicy: target.challengePolicy, preAlarmPolicy: target.preAlarmPolicy,
            createdAt: target.createdAt, updatedAt: max(now, target.createdAt),
            revision: target.revision + 1)
    }

    /// The command the user submits to save this proposal — a plain `.update`. It is the **only**
    /// mutating exit from a proposal, and it changes nothing until `AlarmCommandProcessor.process`
    /// authorizes and applies it: a critical / imminent alarm's update returns `.needsConfirmation`
    /// there (#6). Returns `nil` when the proposed copy is invalid (see `proposedAlarm`).
    func command(now: Date) -> AlarmCommand? {
        proposedAlarm(now: now).map(AlarmCommand.update)
    }

    /// A read-only preview of when the *retimed* alarm would next fire, for the review UI to display
    /// alongside the original — computed through the pure scheduling engine. This mutates nothing; it
    /// does **not** schedule anything. `nil` means the proposed schedule can never ring (e.g. a
    /// one-time date/time already in the past), which the UI must treat as not-saveable, exactly as
    /// the create/edit flow does. The alarm's own enabled flag is not consulted (pure primitive).
    func previewNextOccurrence(after now: Date, deviceTimeZone: TimeZone) -> Date? {
        guard let candidate = proposedAlarm(now: now) else { return nil }
        return Self.engine.nextOccurrence(
            for: candidate, after: now, deviceTimeZone: deviceTimeZone)
    }

    // MARK: - Pure helpers

    private static let engine = AlarmSchedulingEngine()

    /// The target's schedule with the proposed wall-clock time substituted (and, for a one-time
    /// alarm, the proposed date when supplied). The anchor zone and recurrence days are preserved.
    private var retimedSchedule: ScheduleRule {
        switch target.schedule {
        case .weekly(let weekly):
            return .weekly(
                WeeklySchedule(days: weekly.days, time: proposedTime, timeZone: weekly.timeZone))
        case .oneTime(let oneTime):
            return .oneTime(
                OneTimeSchedule(
                    date: proposedDate ?? oneTime.date, time: proposedTime,
                    timeZone: oneTime.timeZone))
        }
    }
}
