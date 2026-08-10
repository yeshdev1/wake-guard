import Foundation

/// Resolves overlapping / duplicate sleep samples into a single, non-overlapping timeline (WG-122).
/// Sleep data routinely overlaps — an iPhone and a Watch both report the night, an `inBed` span wraps
/// `asleep` sub-intervals — so overlaps must be resolved before any duration is summed, or time is
/// double-counted. At every instant the **highest-priority** covering category wins
/// (`awake > asleep > inBed`); adjacent equal-category runs are merged. Pure and deterministic.
enum SleepTimeline {

    static func normalize(_ samples: [SleepSample]) -> [SleepSample] {
        let valid = samples.filter { $0.interval.duration > 0 }
        guard !valid.isEmpty else { return [] }

        // Sweep over every boundary instant; each elementary slice lies fully inside or fully outside
        // each sample, so the winning category is well-defined per slice.
        let boundaries = Set(valid.flatMap { [$0.interval.start, $0.interval.end] }).sorted()
        var segments: [SleepSample] = []
        for index in 0..<(boundaries.count - 1) {
            let (lower, upper) = (boundaries[index], boundaries[index + 1])
            guard upper > lower else { continue }
            let covering = valid.filter { $0.interval.start <= lower && $0.interval.end >= upper }
            // Pick the winning category by a **total order** (priority, then rawValue) so the result is
            // deterministic regardless of input order even if two categories ever shared a priority —
            // the docstring promises purity/determinism, so it must not rest on priorities being distinct.
            guard
                let winner = covering.map(\.category).max(by: {
                    ($0.overlapPriority, $0.rawValue) < ($1.overlapPriority, $1.rawValue)
                })
            else { continue }
            append(winner, lower, upper, into: &segments)
        }
        return segments
    }

    /// Append `[lower, upper)` as `category`, merging with the previous segment when they are the same
    /// category and touch (so overlapping same-category samples become one union interval).
    private static func append(
        _ category: SleepCategory, _ lower: Date, _ upper: Date, into segments: inout [SleepSample]
    ) {
        if let last = segments.last, last.category == category, last.interval.end == lower {
            segments[segments.count - 1] = SleepSample(
                category: category, interval: DateInterval(start: last.interval.start, end: upper))
        } else {
            segments.append(
                SleepSample(category: category, interval: DateInterval(start: lower, end: upper)))
        }
    }
}

/// A **bounded** query window for sleep samples (WG-122): clamps a requested range to at most
/// `maxLookback` before `end`, so a query can never scan an unbounded history. An empty window (requested
/// start at/after `end`) yields no query.
struct SleepQueryWindow: Sendable, Equatable {
    let start: Date
    let end: Date

    /// A conservative default lookback — the sleep-consistency calculator (WG-123) needs only recent
    /// nights, so two weeks is ample and keeps the HealthKit scan cheap.
    static let defaultMaxLookback: TimeInterval = 14 * 86_400

    init(end: Date, requestedStart: Date, maxLookback: TimeInterval = defaultMaxLookback) {
        let earliest = end.addingTimeInterval(-max(0, maxLookback))
        self.end = end
        self.start = min(max(requestedStart, earliest), end)
    }

    var isEmpty: Bool { start >= end }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Port for querying sleep samples (WG-122). The real adapter (`HealthInfrastructure`) runs a **bounded,
/// cancelable** HealthKit query and returns **overlap-resolved** samples; the domain stays
/// framework-independent. Optional throughout: a denied/empty source yields no samples (the readiness
/// feature then reports unavailable, WG-123), never a fabricated value.
protocol SleepSampleQuerying: Sendable {
    /// Normalized sleep samples whose **start** falls within the bounded window `[start, end]` (clamped;
    /// the real adapter uses a strict-start predicate, so a stale multi-day straggler that merely overlaps
    /// the window edge is excluded — the safe choice for a recent-nights estimate). Respects task
    /// cancellation. Throws only on a genuine query error — an empty result is `[]`, not an error.
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample]
}
