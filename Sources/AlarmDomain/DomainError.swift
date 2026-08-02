/// Errors thrown when constructing or decoding an alarm domain value with
/// out-of-range or inconsistent data. Validation lives in the value types'
/// throwing initializers (and their `Decodable` conformances re-validate), so
/// an invalid domain value cannot be constructed or decoded.
enum DomainError: Error, Equatable, Sendable {
    case invalidTimeOfDay(hour: Int, minute: Int)
    case invalidCalendarDate(year: Int, month: Int, day: Int)
    case emptyWeekdaySet
    case timeZoneNotIANA(String)
    case invalidSnoozePolicy(reason: String)
    case invalidPreAlarmPolicy(reason: String)
    case invalidWalkChallenge(reason: String)
    case invalidAlarm(reason: String)
}
