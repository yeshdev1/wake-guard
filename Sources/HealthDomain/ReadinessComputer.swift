import Foundation

/// Assembles the readiness estimate from a window of normalized sleep samples (WG-130) — the pure glue
/// between the WG-122 query and the WG-123/124/125 calculators. Groups samples into **nights** (by gap),
/// derives each night's duration + midpoint, and folds them into a `ReadinessAssessment`. **Empty or
/// missing data yields an assessment with no factors** (→ "not enough data" UI), never a crash and never
/// a fabricated value — so a denied/revoked query (which returns no samples) degrades gracefully.
enum ReadinessComputer {
    /// The gap between consecutive sleep intervals above which a new night begins.
    static let nightGap: TimeInterval = 6 * 3_600

    static func readiness(from samples: [SleepSample], need: SleepNeed, calendar: Calendar)
        -> ReadinessAssessment
    {
        let nights = nights(from: samples)
        let nightlyDurations = nights.map { SleepMetrics.asleepDuration($0) }
        let lastNightAsleep = nights.last.flatMap { SleepMetrics.asleepDuration($0) }
        let midpointSeconds = nights.compactMap { night in
            SleepMetrics.sleepMidpoint(night).map {
                SleepMetrics.localSecondsOfDay($0, in: calendar.timeZone)
            }
        }
        return ReadinessModel.assess(
            ReadinessInputs(
                lastNightAsleep: lastNightAsleep,
                consistency: SleepMetrics.consistency(ofLocalSeconds: midpointSeconds),
                debt: SleepDebt.estimate(nightlyDurations: nightlyDurations, need: need),
                need: need))
    }

    /// Segment samples into nights: sort by start, and begin a new night whenever the gap from the
    /// previous interval's end exceeds `nightGap`. Robust to sleep spanning midnight (no calendar-day
    /// ambiguity).
    static func nights(from samples: [SleepSample], maxGap: TimeInterval = nightGap)
        -> [[SleepSample]]
    {
        let sorted = samples.sorted { $0.interval.start < $1.interval.start }
        var groups: [[SleepSample]] = []
        for sample in sorted {
            if let lastEnd = groups.last?.last?.interval.end,
                sample.interval.start.timeIntervalSince(lastEnd) <= maxGap
            {
                groups[groups.count - 1].append(sample)
            } else {
                groups.append([sample])
            }
        }
        return groups
    }
}
