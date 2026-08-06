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
    /// A fixed id for the throwaway preview/validation alarm, so computing the preview never
    /// consumes a real identifier.
    private static let previewID = AlarmID(UUID())

    init(
        processor: any AlarmCommandProcessing, clock: any WallClock, ids: any IdentifierGenerator,
        deviceTimeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.processor = processor
        self.clock = clock
        self.ids = ids
        self.deviceTimeZone = deviceTimeZone
        let now = clock.now
        self.time = now
        self.date = now
        self.weekdays = Set(Weekday.allCases)
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

    func save() async -> SaveResult {
        // Re-validate at submit time, not only when enabling the button: the chosen minute
        // can lapse into the past between the preview and the Save tap, and a past-due alarm
        // must never be saved (it could never ring). `nextOccurrence` uses the throwaway
        // preview id, so an invalid save consumes no real identifier.
        guard nextOccurrence != nil, let alarm = buildAlarm(id: AlarmID(ids.next())) else {
            return .invalid
        }
        isSaving = true
        defer { isSaving = false }
        switch await processor.process(
            .create(alarm), from: .userInterface, by: .user, userConfirmed: false)
        {
        // The alarm is persisted locally on both outcomes; `.uncertain` is the deferred-sync
        // case (the system schedule is placed later by reconciliation) — still a create.
        case .applied, .uncertain:
            return .created
        case .rejected(let reason), .failed(let reason):
            return .failed(reason: reason)
        case .noOp, .unsupported:
            return .failed(reason: "The alarm could not be created.")
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
}
