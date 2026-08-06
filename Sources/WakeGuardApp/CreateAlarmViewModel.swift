import Foundation
import Observation

/// Drives the create-alarm flow (WG-042): holds the form state, builds a validated domain
/// `Alarm`, previews its next occurrence live, and submits it through the command-processing
/// boundary (never touching persistence or the adapter directly, #2/#3). Read-only until the
/// user saves.
@MainActor
@Observable
final class CreateAlarmViewModel {

    /// The MVP schedule types.
    enum ScheduleKind: Sendable, CaseIterable, Hashable { case weekly, oneTime }

    enum SaveResult: Equatable, Sendable {
        case created
        /// The form did not describe a saveable alarm (should be unreachable — the UI
        /// disables Save when `canSave` is false).
        case invalid
        /// The policy requires explicit confirmation (editing a critical / imminent alarm, #6);
        /// `reason` is the prompt. The view confirms and calls `save(confirmed: true)`.
        case needsConfirmation(reason: String)
        case failed(reason: String)
    }

    // Form state (view-bound).
    var label = ""
    var kind: ScheduleKind = .weekly
    var time: Date
    var weekdays: Set<Weekday>
    var date: Date
    private(set) var isSaving = false

    private let processor: any AlarmCommandProcessing
    private let clock: any WallClock
    private let ids: any IdentifierGenerator
    private let deviceTimeZone: @Sendable () -> TimeZone
    private let engine = AlarmSchedulingEngine()
    /// The alarm being edited, or `nil` when creating (WG-043).
    private let editing: Alarm?
    /// A fixed id for the throwaway preview/validation alarm, so computing the preview never
    /// consumes a real identifier.
    private static let previewID = AlarmID(UUID())

    var isEditing: Bool { editing != nil }

    init(
        editing: Alarm? = nil, processor: any AlarmCommandProcessing, clock: any WallClock,
        ids: any IdentifierGenerator,
        deviceTimeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.editing = editing
        self.processor = processor
        self.clock = clock
        self.ids = ids
        self.deviceTimeZone = deviceTimeZone
        let now = clock.now
        if let editing {
            let seed = Self.seed(from: editing.schedule, now: now, zone: deviceTimeZone())
            self.label = editing.label
            self.kind = seed.kind
            self.time = seed.time
            self.weekdays = seed.weekdays
            self.date = seed.date
        } else {
            self.time = now
            self.date = now
            self.weekdays = Set(Weekday.allCases)
        }
    }

    /// The next time this alarm would fire, for the live preview. This is also the
    /// **validation**: `nil` means the alarm can never ring (a one-time date/time in the
    /// past, or no weekdays selected), so it must not be saveable — CLAUDE.md "unsafe/invalid
    /// dates cannot be saved."
    var nextOccurrence: Date? {
        buildAlarm(id: Self.previewID).flatMap {
            engine.nextOccurrence(for: $0, after: clock.now, deviceTimeZone: deviceTimeZone())
        }
    }

    var canSave: Bool { nextOccurrence != nil }

    func save(confirmed: Bool = false) async -> SaveResult {
        // Re-validate at submit time, not only when enabling the button: the chosen minute can
        // lapse into the past between the preview and the Save tap, and a past-due alarm must
        // never be saved (it could never ring).
        guard nextOccurrence != nil else { return .invalid }
        let command: AlarmCommand
        if let editing {
            guard let updated = buildAlarm(id: editing.id, basedOn: editing) else {
                return .invalid
            }
            command = .update(updated)
        } else {
            // `nextOccurrence` uses the throwaway preview id, so an invalid create consumes none.
            guard let created = buildAlarm(id: AlarmID(ids.next())) else { return .invalid }
            command = .create(created)
        }
        isSaving = true
        defer { isSaving = false }
        switch await processor.process(
            command, from: .userInterface, by: .user, userConfirmed: confirmed)
        {
        // The alarm is persisted locally on both outcomes; `.uncertain` is the deferred-sync
        // case (the system schedule is placed later by reconciliation) — still saved.
        case .applied, .uncertain:
            return .created
        case .needsConfirmation(let reason):
            // Editing a critical / imminent alarm needs explicit confirmation (#6); the view
            // prompts and calls save(confirmed: true).
            return .needsConfirmation(reason: reason)
        case .rejected(let reason), .failed(let reason):
            // Not confirmable (fail-closed read error, etc.) — surface as a plain failure.
            return .failed(reason: reason)
        case .noOp, .unsupported:
            return .failed(reason: "The alarm could not be saved.")
        }
    }

    private func buildAlarm(id: AlarmID) -> Alarm? {
        guard let schedule = buildSchedule() else { return nil }
        let now = clock.now
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return try? Alarm(
            id: id, label: trimmed, schedule: schedule, createdAt: now, updatedAt: now)
    }

    private func buildSchedule() -> ScheduleRule? {
        let zone = deviceTimeZone()
        // The device zone is always a real IANA zone; a fixed-offset ("GMT…") one is rejected.
        guard let iana = try? IANATimeZone(identifier: zone.identifier) else { return nil }
        var calendar = Calendar.current
        calendar.timeZone = zone
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        guard let hour = timeParts.hour, let minute = timeParts.minute,
            let timeOfDay = try? TimeOfDay(hour: hour, minute: minute)
        else { return nil }
        switch kind {
        case .weekly:
            guard let days = try? WeekdaySet(weekdays) else { return nil }  // empty → not saveable
            return .weekly(WeeklySchedule(days: days, time: timeOfDay, timeZone: iana))
        case .oneTime:
            let dayParts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = dayParts.year, let month = dayParts.month, let day = dayParts.day,
                let calendarDate = try? CalendarDate(year: year, month: month, day: day)
            else { return nil }
            return .oneTime(OneTimeSchedule(date: calendarDate, time: timeOfDay, timeZone: iana))
        }
    }

    /// Build the edited alarm — same id, bumped revision, other fields preserved (only the
    /// label + schedule are editable here; criticality is WG-044).
    private func buildAlarm(id: AlarmID, basedOn existing: Alarm) -> Alarm? {
        guard let schedule = buildSchedule() else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return try? Alarm(
            id: existing.id, label: trimmed, isEnabled: existing.isEnabled, schedule: schedule,
            travelBehavior: existing.travelBehavior, criticality: existing.criticality,
            sound: existing.sound, snoozePolicy: existing.snoozePolicy,
            challengePolicy: existing.challengePolicy, preAlarmPolicy: existing.preAlarmPolicy,
            createdAt: existing.createdAt, updatedAt: clock.now, revision: existing.revision + 1)
    }

    /// The form fields decomposed from an existing schedule for editing.
    private struct FormSeed {
        let kind: ScheduleKind
        let time: Date
        let weekdays: Set<Weekday>
        let date: Date
    }

    private static func seed(from schedule: ScheduleRule, now: Date, zone: TimeZone) -> FormSeed {
        var calendar = Calendar.current
        calendar.timeZone = zone
        switch schedule {
        case .weekly(let weekly):
            let time = calendar.date(
                bySettingHour: weekly.time.hour, minute: weekly.time.minute, second: 0, of: now)
            return FormSeed(kind: .weekly, time: time ?? now, weekdays: weekly.days.days, date: now)
        case .oneTime(let oneTime):
            let time = calendar.date(
                bySettingHour: oneTime.time.hour, minute: oneTime.time.minute, second: 0, of: now)
            var parts = DateComponents()
            parts.year = oneTime.date.year
            parts.month = oneTime.date.month
            parts.day = oneTime.date.day
            parts.hour = 12
            return FormSeed(
                kind: .oneTime, time: time ?? now, weekdays: Set(Weekday.allCases),
                date: calendar.date(from: parts) ?? now)
        }
    }
}
