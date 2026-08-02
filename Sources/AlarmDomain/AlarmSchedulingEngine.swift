import Foundation

/// Pure next-occurrence calculation for a `ScheduleRule`. Deterministic: a pure
/// function of the rule, the reference instant `now`, and the injected
/// `timeZone` — no `Date()`, no ambient state (CLAUDE.md: route time reads through
/// an injected clock; here the caller passes the clock's reading as `now`).
///
/// The rule's wall-clock times are interpreted in the **injected** `timeZone`.
/// Selecting that zone per the alarm's `TravelBehavior` — the device's current
/// zone for follow-local, the rule's anchor zone for fixed — is WG-021. Explicit
/// DST gap/ambiguous-time policy is WG-022 and International Date Line behavior is
/// WG-023; here Foundation's calendar resolution handles those edges.
struct AlarmSchedulingEngine: Sendable {

    /// The earliest occurrence of `rule` strictly after `now`, interpreted in
    /// `timeZone`. Returns `nil` for a one-time schedule whose instant is not
    /// after `now` (a past one-time alarm has no next occurrence). An occurrence
    /// falling exactly on `now` is not returned — "next" means strictly future.
    func nextOccurrence(of rule: ScheduleRule, after now: Date, in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        switch rule {
        case .oneTime(let schedule):
            return nextOneTime(schedule, after: now, in: calendar)
        case .weekly(let schedule):
            return nextWeekly(schedule, after: now, in: calendar)
        }
    }

    private func nextOneTime(_ schedule: OneTimeSchedule, after now: Date, in calendar: Calendar)
        -> Date?
    {
        var components = DateComponents()
        components.year = schedule.date.year
        components.month = schedule.date.month
        components.day = schedule.date.day
        components.hour = schedule.time.hour
        components.minute = schedule.time.minute
        components.second = 0
        guard let instant = calendar.date(from: components), instant > now else { return nil }
        return instant
    }

    private func nextWeekly(_ schedule: WeeklySchedule, after now: Date, in calendar: Calendar)
        -> Date?
    {
        // The earliest strictly-future match across the (non-empty) weekday set.
        var candidates: [Date] = []
        for weekday in schedule.days.days {
            var match = DateComponents()
            match.weekday = weekday.rawValue
            match.hour = schedule.time.hour
            match.minute = schedule.time.minute
            match.second = 0
            if let candidate = calendar.nextDate(
                after: now, matching: match, matchingPolicy: .nextTime)
            {
                candidates.append(candidate)
            }
        }
        return candidates.min()
    }
}
