import Foundation

/// An assumption the parse made that the user should review before confirming (WG-166). Structured, not
/// prose, so the view localizes it — the app never shows an un-localizable AI string.
enum ScheduleAssumption: Sendable, Equatable, Hashable {
    /// The alarm uses the device's current time zone (identifier), not one the user stated.
    case usesCurrentTimeZone(identifier: String)
    /// A one-time alarm resolves to this concrete instant — surfaced so the user sees *which* day.
    case ringsOn(date: Date)
    /// A repeating alarm fires on these weekdays.
    case repeatsWeekly(days: Set<AIWeekday>)
}

/// A review summary of a **validated** alarm and the assumptions behind it (WG-166), shown before the user
/// confirms. Pure presentation built deterministically from a `ValidatedAlarmIntent` — no model
/// involvement — and carries **no criticality** and no command: reviewing it schedules nothing.
struct ParsedScheduleSummary: Sendable, Equatable, Hashable {
    let time: TimeOfDay
    let recurrence: ValidatedRecurrence
    let timeZoneIdentifier: String
    let assumptions: [ScheduleAssumption]

    static func summary(for intent: ValidatedAlarmIntent) -> ParsedScheduleSummary {
        var assumptions: [ScheduleAssumption] = [
            .usesCurrentTimeZone(identifier: intent.timeZone.identifier)
        ]
        switch intent.recurrence {
        case .oneTime(let fireDate):
            assumptions.append(.ringsOn(date: fireDate))
        case .weekly(let days):
            assumptions.append(.repeatsWeekly(days: days))
        }
        return ParsedScheduleSummary(
            time: intent.time, recurrence: intent.recurrence,
            timeZoneIdentifier: intent.timeZone.identifier, assumptions: assumptions)
    }
}
