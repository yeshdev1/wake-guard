/// How an alarm recurs. The two intents of SAFETY_INVARIANTS #12 (a specific
/// zoned instant vs. a repeating wall-clock time) are the two cases; whether the
/// wall-clock times follow the device or stay in the original zone is the
/// alarm's `TravelBehavior`. Occurrence calculation is WG-020, not the model.
enum ScheduleRule: Codable, Sendable, Equatable, Hashable {
    case oneTime(OneTimeSchedule)
    case weekly(WeeklySchedule)

    /// The zone the wall-clock times are anchored to (the "original time zone").
    var anchorTimeZone: IANATimeZone {
        switch self {
        case .oneTime(let schedule): schedule.timeZone
        case .weekly(let schedule): schedule.timeZone
        }
    }

    /// The wall-clock time the alarm fires at.
    var time: TimeOfDay {
        switch self {
        case .oneTime(let schedule): schedule.time
        case .weekly(let schedule): schedule.time
        }
    }
}

/// A single firing at a specific calendar date and wall-clock time in one zone.
struct OneTimeSchedule: Codable, Sendable, Equatable, Hashable {
    let date: CalendarDate
    let time: TimeOfDay
    let timeZone: IANATimeZone
}

/// A repeating firing on one or more weekdays at a wall-clock time, anchored to
/// one zone.
struct WeeklySchedule: Codable, Sendable, Equatable, Hashable {
    let days: WeekdaySet
    let time: TimeOfDay
    let timeZone: IANATimeZone
}
