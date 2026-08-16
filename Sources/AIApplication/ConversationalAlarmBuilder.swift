import Foundation

/// The complete set of choices the conversational flow gathers before scheduling (WG-298): the validated
/// schedule plus the criticality and wake-challenge the user **explicitly confirmed** in the review step.
/// The on-device model never emits criticality — it is set from a deterministic keyword hint plus the
/// user's confirmation in the preview (#31 stays intact; amends WG-245 Finding A per the WG-298 ADR).
struct ConversationalAlarmSpec: Sendable, Equatable {
    let intent: ValidatedAlarmIntent
    let criticality: Criticality
    let challenge: ChallengePolicy
}

/// Builds an alarm from a validated natural-language intent plus the user-confirmed criticality and
/// challenge (WG-166 / WG-298 commit). Criticality is still **never** taken from the model's output —
/// only from the user's explicit choice in the review step (#31). Returns `nil` if the intent can't form a
/// valid schedule — the conversational flow then fails closed rather than creating a malformed alarm.
enum ConversationalAlarmBuilder {
    static func alarm(from spec: ConversationalAlarmSpec, id: UUID, now: Date) -> Alarm? {
        guard let schedule = scheduleRule(from: spec.intent) else { return nil }
        return try? Alarm(
            id: AlarmID(id), label: "Alarm", schedule: schedule, criticality: spec.criticality,
            challengePolicy: spec.challenge, createdAt: now, updatedAt: now)
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
