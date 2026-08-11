import Foundation

/// Builds an alarm from a validated natural-language intent (WG-166 commit). Criticality is **never** taken
/// from parsed text (#31 / WG-245 Finding A): the policy/UI assign it separately, so an alarm created this
/// way is always `.standard`. Returns `nil` if the intent can't form a valid schedule — the conversational
/// flow then fails closed rather than creating a malformed alarm.
enum ConversationalAlarmBuilder {
    static func alarm(from intent: ValidatedAlarmIntent, id: UUID, now: Date) -> Alarm? {
        guard let schedule = scheduleRule(from: intent) else { return nil }
        return try? Alarm(
            id: AlarmID(id), label: "Alarm", schedule: schedule, criticality: .standard,
            createdAt: now, updatedAt: now)
    }

    /// Map the validated recurrence + time + zone onto a domain `ScheduleRule`.
    static func scheduleRule(from intent: ValidatedAlarmIntent) -> ScheduleRule? {
        switch intent.recurrence {
        case .weekly(let aiDays):
            guard let days = try? WeekdaySet(Set(aiDays.map(weekday(from:)))) else { return nil }
            return .weekly(WeeklySchedule(days: days, time: intent.time, timeZone: intent.timeZone))
        case .oneTime(let fireDate):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = intent.timeZone.timeZone
            let parts = calendar.dateComponents([.year, .month, .day], from: fireDate)
            guard let year = parts.year, let month = parts.month, let day = parts.day,
                let date = try? CalendarDate(year: year, month: month, day: day)
            else { return nil }
            return .oneTime(
                OneTimeSchedule(date: date, time: intent.time, timeZone: intent.timeZone))
        }
    }

    private static func weekday(from ai: AIWeekday) -> Weekday {
        switch ai {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        }
    }
}
