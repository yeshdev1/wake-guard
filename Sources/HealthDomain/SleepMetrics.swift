import Foundation

/// Sleep-timing consistency across several nights (WG-123). Reports the **typical** sleep midpoint as a
/// local time-of-day and how much it varies night to night — the smaller `meanDeviationMinutes`, the more
/// regular the schedule. Descriptive only (no score, no judgement); the readiness model (WG-125)
/// interprets it.
struct SleepConsistency: Sendable, Equatable, Hashable {
    /// The circular-mean sleep midpoint, as seconds past local midnight `[0, 86400)`.
    let typicalMidpointSecondsOfDay: Int
    /// The mean absolute deviation of the nightly midpoints from the typical one, in minutes (shorter-arc,
    /// so 23:50 and 00:10 are 20 minutes apart, not 23h40m).
    let meanDeviationMinutes: Double
    /// How many nights this summarizes.
    let nights: Int
}

/// Transparent sleep-duration and consistency formulas over WG-122's normalized samples (WG-123). Pure —
/// every result is a deterministic function of the inputs and an injected calendar/zone. **Missing data
/// returns `nil` (unavailable), never a fabricated value.** Time-zone changes are handled by design:
/// durations are absolute elapsed time (DST-safe), and consistency is measured in each night's **local**
/// time-of-day (so a stable local bedtime stays "consistent" across travel) using circular statistics
/// (so midnight wraparound doesn't distort it).
enum SleepMetrics {
    private static let secondsPerDay = 86_400

    /// Total time **asleep** in one night's normalized samples — the sum of `.asleep` interval durations
    /// (the WG-122 timeline is non-overlapping, so this can't double-count). `nil` when there is no asleep
    /// sample: missing data is **unavailable**, never reported as `0`.
    static func asleepDuration(_ samples: [SleepSample]) -> TimeInterval? {
        let asleep = samples.filter { $0.category == .asleep }
        guard !asleep.isEmpty else { return nil }
        return asleep.reduce(0) { $0 + $1.interval.duration }
    }

    /// The midpoint of the night's asleep span (first asleep start … last asleep end), or `nil` if there
    /// is no asleep sample. An **absolute** instant — time-zone-independent by construction.
    static func sleepMidpoint(_ samples: [SleepSample]) -> Date? {
        let asleep = samples.filter { $0.category == .asleep }
        guard let first = asleep.map(\.interval.start).min(),
            let last = asleep.map(\.interval.end).max()
        else { return nil }
        return first.addingTimeInterval(last.timeIntervalSince(first) / 2)
    }

    /// The local time-of-day of `date` in `zone`, as seconds past midnight `[0, 86400)`. Computing this
    /// **per night in that night's zone** is how travel is covered — a stable local bedtime yields the
    /// same value at home or away.
    static func localSecondsOfDay(_ date: Date, in zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0) * 3_600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }

    /// Sleep-timing consistency from each night's **local** midpoint-seconds (compute each via
    /// `localSecondsOfDay` in that night's zone). Uses the circular mean + mean absolute deviation, so a
    /// bedtime straddling midnight isn't treated as ~12 hours off. `nil` for fewer than 2 nights —
    /// consistency of a single night is **unavailable**, not fabricated.
    static func consistency(ofLocalSeconds seconds: [Int]) -> SleepConsistency? {
        guard seconds.count >= 2 else { return nil }
        let angles = seconds.map { Double($0) / Double(secondsPerDay) * 2 * .pi }
        let meanCos = angles.map(cos).reduce(0, +) / Double(angles.count)
        let meanSin = angles.map(sin).reduce(0, +) / Double(angles.count)
        let meanSeconds = normalizedSeconds(
            atan2(meanSin, meanCos) / (2 * .pi) * Double(secondsPerDay))
        let deviations = seconds.map { circularDistanceSeconds(Double($0), meanSeconds) }
        let meanAbsoluteDeviation = deviations.reduce(0, +) / Double(deviations.count)
        return SleepConsistency(
            typicalMidpointSecondsOfDay: Int(meanSeconds.rounded()) % secondsPerDay,
            meanDeviationMinutes: meanAbsoluteDeviation / 60,
            nights: seconds.count)
    }

    /// Shorter-arc distance between two times-of-day, in seconds.
    private static func circularDistanceSeconds(_ lhs: Double, _ rhs: Double) -> Double {
        let raw = abs(lhs - rhs)
        return min(raw, Double(secondsPerDay) - raw)
    }

    /// Wrap a (possibly negative) seconds value into `[0, 86400)`.
    private static func normalizedSeconds(_ seconds: Double) -> Double {
        let remainder = seconds.truncatingRemainder(dividingBy: Double(secondsPerDay))
        return remainder < 0 ? remainder + Double(secondsPerDay) : remainder
    }
}
