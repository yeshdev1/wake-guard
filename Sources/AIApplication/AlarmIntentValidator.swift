import Foundation

/// Why the deterministic validator rejected a proposed alarm (WG-165). Each maps to a specific, honest
/// user message; every rejection keeps the app safe by refusing to schedule.
enum AlarmIntentRejection: String, Sendable, Equatable, Hashable, CaseIterable {
    case invalidTimeZone
    case timeOutOfRange
    case inThePast
    case unsupportedRecurrence
    case unsafeValue
}

/// How a validated alarm recurs (WG-165). A one-time alarm carries its resolved absolute fire instant; a
/// weekly alarm carries its day set.
enum ValidatedRecurrence: Sendable, Equatable, Hashable {
    case oneTime(fireDate: Date)
    case weekly(Set<AIWeekday>)
}

/// A validated, authorizable alarm intent (WG-165) — the deterministic result the orchestrator (WG-172)
/// hands to the command/policy path. It carries a resolved `TimeOfDay`, recurrence, and an
/// `IANATimeZone`, and **no criticality** (#31): the validator never sets criticality.
struct ValidatedAlarmIntent: Sendable, Equatable, Hashable {
    let time: TimeOfDay
    let recurrence: ValidatedRecurrence
    let timeZone: IANATimeZone
}

/// The result of deterministic validation (WG-165): a validated intent or a specific rejection.
enum AlarmIntentValidation: Sendable, Equatable, Hashable {
    case valid(ValidatedAlarmIntent)
    case rejected(AlarmIntentRejection)
}

/// Deterministically validates a proposed alarm before it can become a command (WG-165). It is **wholly
/// independent of the model** — a pure function of the draft, a time-zone identifier, and `now` — so a
/// parsed *or* hand-entered intent is held to the same rules. It rejects **invalid zones** (non-IANA /
/// GMT-family / injection strings, via `IANATimeZone`, #11), **out-of-range times** (via `TimeOfDay`),
/// **past** one-time alarms, **unsupported recurrence** (a weekly alarm that also carries a one-time
/// offset), and **unsafe values** (an offset beyond the horizon). It never sets criticality (#31).
struct AlarmIntentValidator: Sendable {
    /// The furthest ahead a one-time alarm may be scheduled; a larger offset is an unsafe value.
    static let maxDayOffset = 366

    func validate(
        _ draft: AlarmDraftPreview, timeZoneIdentifier: String, now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> AlarmIntentValidation {
        guard let zone = try? IANATimeZone(identifier: timeZoneIdentifier) else {
            return .rejected(.invalidTimeZone)
        }
        guard let time = try? TimeOfDay(hour: draft.hour, minute: draft.minute) else {
            return .rejected(.timeOutOfRange)
        }
        if !draft.weekdays.isEmpty {
            // A weekly alarm may not also carry a one-time offset — that is a contradictory recurrence.
            guard draft.dayOffset == nil else { return .rejected(.unsupportedRecurrence) }
            return .valid(intent(time: time, recurrence: .weekly(draft.weekdays), zone: zone))
        }
        return validateOneTime(draft: draft, time: time, zone: zone, now: now, calendar: calendar)
    }

    private func validateOneTime(
        draft: AlarmDraftPreview, time: TimeOfDay, zone: IANATimeZone, now: Date, calendar: Calendar
    ) -> AlarmIntentValidation {
        let offset = draft.dayOffset ?? 0
        guard offset >= 0 else { return .rejected(.inThePast) }
        guard offset <= Self.maxDayOffset else { return .rejected(.unsafeValue) }
        guard
            let fireDate = Self.fireDate(
                time: time, dayOffset: offset, now: now, zone: zone.timeZone, calendar: calendar)
        else {
            return .rejected(.unsafeValue)
        }
        guard fireDate > now else { return .rejected(.inThePast) }
        return .valid(intent(time: time, recurrence: .oneTime(fireDate: fireDate), zone: zone))
    }

    private func intent(
        time: TimeOfDay, recurrence: ValidatedRecurrence, zone: IANATimeZone
    ) -> ValidatedAlarmIntent {
        ValidatedAlarmIntent(time: time, recurrence: recurrence, timeZone: zone)
    }

    private static func fireDate(
        time: TimeOfDay, dayOffset: Int, now: Date, zone: TimeZone, calendar: Calendar
    ) -> Date? {
        var zoned = calendar
        zoned.timeZone = zone
        guard let base = zoned.date(byAdding: .day, value: dayOffset, to: now) else { return nil }
        var components = zoned.dateComponents([.year, .month, .day], from: base)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return zoned.date(from: components)
    }
}
