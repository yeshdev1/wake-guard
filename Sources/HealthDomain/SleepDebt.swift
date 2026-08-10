import Foundation

/// The user's **configurable** target sleep per night (WG-124). Clamped to a sane 4–12 h so a bad
/// config can't produce an absurd debt. The 8 h default is a common planning assumption — **not** a
/// medical prescription (#39).
struct SleepNeed: Sendable, Equatable, Hashable, Codable {
    let perNight: TimeInterval

    static let minimum: TimeInterval = 4 * 3_600
    static let maximum: TimeInterval = 12 * 3_600
    static let `default` = SleepNeed(perNight: 8 * 3_600)

    init(perNight: TimeInterval) {
        let sane = perNight.isFinite ? perNight : Self.defaultSeconds
        self.perNight = min(max(sane, Self.minimum), Self.maximum)
    }

    private static let defaultSeconds: TimeInterval = 8 * 3_600
}

/// A **conservative** accumulated sleep-debt estimate (WG-124) — descriptive, with its assumptions made
/// explicit and **no medical claim** (#39). It is `>= 0`, capped at a conservative ceiling, and counts
/// only nights with data.
struct SleepDebtEstimate: Sendable, Equatable, Hashable {
    /// The estimated accumulated shortfall, seconds (`>= 0`).
    let debt: TimeInterval
    /// The sleep need the estimate assumed.
    let sleepNeed: TimeInterval
    /// Nights with sleep data that were counted.
    let nightsCounted: Int
    /// Nights with no data — **excluded**, never assumed to be a shortfall or a full night.
    let nightsMissing: Int
    /// Whether the total hit the conservative ceiling (so it never overstates a deficit).
    let wasCapped: Bool

    /// A plain-language list of the estimate's assumptions — so the user sees *how* it was reached, and
    /// that it is a rough planning estimate, **not** a diagnosis or a medical measure (#39).
    var assumptions: [String] {
        [
            "Based on a sleep need of \(Self.hoursText(sleepNeed)) per night, which you can change.",
            "Counts \(nightsCounted) night(s) with sleep data; \(nightsMissing) missing night(s) are "
                + "excluded, not assumed.",
            "Nights you slept more than your need reduce the total — recovery sleep counts.",
            wasCapped
                ? "Capped at a conservative maximum, so it never overstates a deficit."
                : "Floored at zero, so a well-rested stretch shows no debt.",
            "This is a rough estimate to help you plan — not a diagnosis or a medical measure of sleep "
                + "deprivation.",
        ]
    }

    static func hoursText(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let (hours, minutes) = (totalMinutes / 60, totalMinutes % 60)
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

/// Computes the conservative sleep-debt estimate (WG-124). Pure and transparent.
enum SleepDebt {
    /// A conservative estimate over `nightlyDurations` (a `nil` entry is a **missing** night — excluded)
    /// against a configurable `need`. A night's surplus offsets prior shortfall (recovery counts); the
    /// total is **floored at 0** and **capped** at `need x maxNights`, so it can never imply a dramatic
    /// deficit. Returns `nil` when **no** night has data — unavailable, never a fabricated `0`.
    static func estimate(nightlyDurations: [TimeInterval?], need: SleepNeed, maxNights: Int = 7)
        -> SleepDebtEstimate?
    {
        let present = nightlyDurations.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        let rawShortfall = present.reduce(0.0) { $0 + (need.perNight - $1) }
        let ceiling = need.perNight * Double(max(1, maxNights))
        return SleepDebtEstimate(
            debt: min(max(rawShortfall, 0), ceiling),
            sleepNeed: need.perNight,
            nightsCounted: present.count,
            nightsMissing: nightlyDurations.count - present.count,
            wasCapped: rawShortfall > ceiling)
    }
}
