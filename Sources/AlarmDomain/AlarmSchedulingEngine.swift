import Foundation

/// How a scheduled wall-clock time resolved against a DST transition in its zone (WG-022) — a
/// **user-visible** explanation (a UI can say "2:30 doesn't happen that night; your alarm rings at
/// 3:00"). The alarm **always fires**: a spring-forward *gap* fires at the gap's end (never skipped, so
/// a wake alarm is never lost), and a fall-back *duplicate* fires at the **first** (earlier) occurrence
/// (a wake alarm rings at the soonest valid instant, never the later one).
enum DSTResolution: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// The wall-clock time exists exactly once on that date — no adjustment.
    case exact
    /// The wall-clock time falls in a spring-forward gap (it never happens); the alarm fires at the
    /// gap's end instead.
    case skippedToGapEnd
    /// The wall-clock time happens twice on a fall-back day; the alarm fires at the first (earlier) one.
    case ambiguousUsedFirst
    /// The requested calendar **day** does not exist in this zone — an International Date Line crossing
    /// skipped it (WG-023). The alarm fires at the same wall-clock on the **next existing day**; it is
    /// never lost.
    case skippedAcrossDateLine
}

/// Pure next-occurrence calculation for a `ScheduleRule`. Deterministic: a pure function of the rule,
/// the reference instant `now`, and the injected `timeZone` — no `Date()`, no ambient state (CLAUDE.md:
/// route time reads through an injected clock; here the caller passes the clock's reading as `now`).
///
/// The rule's wall-clock times are interpreted in the **injected** `timeZone` (WG-021 selects that zone
/// per the alarm's `TravelBehavior`). **DST policy (WG-022) is explicit and identical for one-time and
/// weekly rules** — both resolve a specific calendar day + wall-clock through the same `resolveDay`: a
/// *skipped* (spring-forward) time fires at the gap's **end** (the DST transition instant), never
/// skipped; a *repeated* (fall-back) time fires at the **first** (earlier) instant. This holds for any
/// DST delta, including Lord Howe's 30-minute shift, because a gap is detected on the intended day
/// itself, not by a time-of-day roll (which would wrongly jump to the next day/week). An International
/// Date Line **whole-day** skip (WG-023) is likewise detected and flagged `.skippedAcrossDateLine` — the
/// alarm fires at the same wall-clock on the next existing day, never lost. Unusual **offsets** (UTC+14,
/// −11, and the 30/45-minute zones like Kathmandu +5:45 and Chatham +12:45) need no special handling:
/// they are plain offsets the calendar already applies.
struct AlarmSchedulingEngine: Sendable {

    /// The earliest occurrence of `rule` strictly after `now`, interpreted in `timeZone`. Returns `nil`
    /// for a one-time schedule whose instant is not after `now`. An occurrence exactly on `now` is not
    /// returned — "next" means strictly future.
    func nextOccurrence(of rule: ScheduleRule, after now: Date, in timeZone: TimeZone) -> Date? {
        resolvedNextOccurrence(of: rule, after: now, in: timeZone)?.date
    }

    /// The next occurrence **plus how its wall-clock time resolved against a DST transition** (WG-022) —
    /// exposed so a UI can explain a skipped/duplicated local time to the user.
    func resolvedNextOccurrence(of rule: ScheduleRule, after now: Date, in timeZone: TimeZone)
        -> (date: Date, resolution: DSTResolution)?
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        switch rule {
        case .oneTime(let schedule):
            guard
                let resolved = resolveDay(
                    year: schedule.date.year, month: schedule.date.month, day: schedule.date.day,
                    time: schedule.time, in: calendar), resolved.date > now
            else { return nil }
            return resolved
        case .weekly(let schedule):
            return earliestWeekly(schedule, after: now, in: calendar)
        }
    }

    /// Resolve the wall-clock `time` on a specific calendar day under the explicit DST policy (WG-022).
    /// Not filtered against `now` — callers do that.
    private func resolveDay(year: Int, month: Int, day: Int, time: TimeOfDay, in calendar: Calendar)
        -> (date: Date, resolution: DSTResolution)?
    {
        var full = DateComponents()
        full.year = year
        full.month = month
        full.day = day
        full.hour = time.hour
        full.minute = time.minute
        full.second = 0
        guard let naive = calendar.date(from: full) else { return nil }
        let wall = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: naive)
        // International Date Line whole-day skip (WG-023): the requested calendar day does not exist in
        // this zone (a Date Line crossing skipped it — e.g. Pacific/Apia's 2011-12-30). `date(from:)`
        // never skips; it advances to the same wall-clock on the next existing day. Flag it so a UI can
        // explain the shift — the alarm still fires, never lost, at the equivalent time on the next day.
        if wall.year != year || wall.month != month || wall.day != day {
            return (naive, .skippedAcrossDateLine)
        }
        // Spring-forward gap on THIS day: `date(from:)` never skips but shifts a gap's wall-clock, so the
        // decoded time differs from what was asked. Resolve to the gap's **end** — the DST transition
        // instant. (A time-of-day roll can't be used: with only 02:00–02:29 missing, a 30-min gap, it
        // would wrongly jump to the next day/week — the WG-022 review BLOCKER.)
        if wall.hour != time.hour || wall.minute != time.minute {
            guard
                let transition = calendar.timeZone.nextDaylightSavingTimeTransition(
                    after: naive.addingTimeInterval(-7200))
            else { return nil }
            return (transition, .skippedToGapEnd)
        }
        // Exact or ambiguous (fall-back): anchor at the day's start and match time-of-day, so the
        // `.first` policy picks the earlier of a repeated pair.
        var dayComponents = DateComponents()
        dayComponents.year = year
        dayComponents.month = month
        dayComponents.day = day
        guard let dayStart = calendar.date(from: dayComponents) else { return nil }
        return next(timeOfDay: time, after: dayStart.addingTimeInterval(-1), in: calendar)
    }

    private func earliestWeekly(_ schedule: WeeklySchedule, after now: Date, in calendar: Calendar)
        -> (date: Date, resolution: DSTResolution)?
    {
        // For each weekday, resolve this-week's occurrence; if its time already passed (≤ now) or the
        // day itself resolves before `now`, roll to the following week. The earliest strictly-future
        // instant across weekdays wins. Each day goes through `resolveDay`, so the DST policy is applied
        // uniformly (no time-of-day roll that could skip a week — the WG-022 review BLOCKER).
        let anchor = calendar.startOfDay(for: now).addingTimeInterval(-1)
        var best: (date: Date, resolution: DSTResolution)?
        for weekday in schedule.days.days {
            var match = DateComponents()
            match.weekday = weekday.rawValue
            guard
                let firstDay = calendar.nextDate(
                    after: anchor, matching: match, matchingPolicy: .nextTime, direction: .forward)
            else { continue }
            for weekOffset in [0, 7] {
                guard let day = calendar.date(byAdding: .day, value: weekOffset, to: firstDay)
                else {
                    continue
                }
                let parts = calendar.dateComponents([.year, .month, .day], from: day)
                guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day,
                    let resolved = resolveDay(
                        year: year, month: month, day: dayOfMonth, time: schedule.time, in: calendar
                    ),
                    resolved.date > now
                else { continue }
                if let current = best {
                    if resolved.date < current.date { best = resolved }
                } else {
                    best = resolved
                }
                break  // the first strictly-future occurrence for this weekday is its earliest
            }
        }
        return best
    }

    /// The next instant matching `timeOfDay` after `after`, under the explicit DST policy, with its
    /// resolution. Used for a day already known not to be a spring-forward gap.
    private func next(timeOfDay: TimeOfDay, after: Date, in calendar: Calendar)
        -> (date: Date, resolution: DSTResolution)?
    {
        var components = DateComponents()
        components.hour = timeOfDay.hour
        components.minute = timeOfDay.minute
        components.second = 0
        guard
            let instant = calendar.nextDate(
                after: after, matching: components, matchingPolicy: .nextTime,
                repeatedTimePolicy: .first, direction: .forward)
        else { return nil }
        return (instant, classify(instant, requested: timeOfDay, in: calendar))
    }

    /// Classify the resolved instant against the requested wall-clock time (WG-022) — robust to any DST
    /// delta (uses the zone's own transition, not a fragile fully-pinned re-match).
    private func classify(_ instant: Date, requested time: TimeOfDay, in calendar: Calendar)
        -> DSTResolution
    {
        let resolved = calendar.dateComponents([.hour, .minute], from: instant)
        if resolved.hour != time.hour || resolved.minute != time.minute {
            return .skippedToGapEnd
        }
        // Repeated (fall-back): `instant` sits within the repeated window immediately before a fall-back
        // transition (its wall-clock recurs after it). `delta` is the offset drop — an hour, or 30 min
        // for Lord Howe. A spring transition has `delta <= 0` and is handled by the gap check above.
        let zone = calendar.timeZone
        guard let transition = zone.nextDaylightSavingTimeTransition(after: instant) else {
            return .exact
        }
        let delta =
            zone.secondsFromGMT(for: transition.addingTimeInterval(-1))
            - zone.secondsFromGMT(for: transition)
        if delta > 0, transition.timeIntervalSince(instant) <= Double(delta) {
            return .ambiguousUsedFirst
        }
        return .exact
    }
}
