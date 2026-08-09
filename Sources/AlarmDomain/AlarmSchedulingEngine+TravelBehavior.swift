import Foundation

/// WG-021: wall-clock (follow-local) vs fixed-zone (preserve-original-zone)
/// semantics. Applies an alarm's `TravelBehavior` to select which zone the base
/// `nextOccurrence(of:after:in:)` interprets the schedule's wall-clock time in,
/// realizing the two intents of SAFETY_INVARIANTS #12.
///
/// Examples — a 07:00 alarm anchored to `Asia/Tokyo`, device now in
/// `America/New_York`:
/// - **follow-local:** fires at 07:00 New York. The wall-clock follows the
///   device, so after travelling the alarm still rings at 7 a.m. local time.
/// - **fixed (stay-fixed):** fires at 07:00 Tokyo — the same absolute instant
///   regardless of travel (18:00 the previous day in New York).
///
/// The schedule's anchor **IANA identifier is always persisted** (it lives in
/// `ScheduleRule.anchorTimeZone`); follow-local only changes which zone the
/// wall-clock is *interpreted* in at compute time, never the stored anchor.
extension AlarmSchedulingEngine {

    /// The zone the alarm's wall-clock times are interpreted in, per its
    /// `TravelBehavior` (#12): the device's current zone for follow-local, the
    /// rule's anchor zone for fixed. `askOnChange` and a region rule fall back to
    /// the **anchor** zone — a schedule is never silently shifted on travel (#16);
    /// the interactive ask / region resolution is E06.
    func schedulingTimeZone(
        for travelBehavior: TravelBehavior, anchor: IANATimeZone, deviceTimeZone: TimeZone
    ) -> TimeZone {
        switch travelBehavior {
        case .followLocal:
            deviceTimeZone
        case .stayFixed, .askOnChange:
            anchor.timeZone
        case .regionRule(let rule):
            switch rule.safeFallback {
            case .followLocal: deviceTimeZone
            case .stayFixed: anchor.timeZone
            }
        }
    }

    /// The next occurrence of `alarm` strictly after `now`, interpreting its
    /// schedule in the zone selected by its `TravelBehavior` (`deviceTimeZone` is
    /// the device's current zone, used for follow-local).
    ///
    /// It does **not** consult `alarm.isEnabled` — this is a pure scheduling
    /// primitive; the caller (WG-026 scheduling / WG-029 reconciliation) decides
    /// whether a disabled alarm should be scheduled at all. Under follow-local a
    /// DST-gap wall-clock is resolved in the **device** zone (explicit gap policy
    /// is WG-022).
    func nextOccurrence(for alarm: Alarm, after now: Date, deviceTimeZone: TimeZone) -> Date? {
        let zone = schedulingTimeZone(
            for: alarm.travelBehavior,
            anchor: alarm.schedule.anchorTimeZone,
            deviceTimeZone: deviceTimeZone)
        // Skip occurrences the user turned off for that day (WG-085): advance past each skipped
        // instant so the *next recurrence* still rings. Bounded — one attempt per skip plus one (the
        // engine returns strictly-increasing instants; the skip set is finite). A one-time alarm whose
        // only occurrence is skipped resolves to `nil` (no ring), correct. Match by **whole second**
        // (occurrences are second-aligned), so the comparison is robust to `Date`'s JSON float
        // round-trip and never traps on a non-finite persisted value — not exact `Double` equality. A
        // follow-local zone change between skip and fire remaps the instant, so it no longer matches
        // and the alarm still rings — the fail-safe direction (#8-adjacent).
        func wholeSecond(_ date: Date) -> Double { date.timeIntervalSince1970.rounded(.towardZero) }
        let skipped = Set(
            alarm.skippedOccurrences.lazy.filter { $0.timeIntervalSince1970.isFinite }
                .map(wholeSecond))
        var cursor = now
        for _ in 0...skipped.count {
            guard let candidate = nextOccurrence(of: alarm.schedule, after: cursor, in: zone) else {
                return nil
            }
            if !skipped.contains(wholeSecond(candidate)) { return candidate }
            cursor = candidate
        }
        return nil
    }
}
