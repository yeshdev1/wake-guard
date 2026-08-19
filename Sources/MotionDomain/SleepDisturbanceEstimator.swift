import Foundation

/// An **estimate** of overnight device disturbances from motion history (WG-310) — the fallback "interrupted
/// sleep" signal for users **without** Apple sleep tracking (no HealthKit `.awake` segments, WG-309). It is
/// an inference of the phone being *handled* (picked up off the nightstand), **not** confirmed screen-on
/// usage — the UI labels it as such. Coarse by design (#41): a pickup count and total moving time, **no
/// timestamps** (when you were disturbed is the sensitive part). Advisory only, never on the alarm path.
struct SleepDisturbances: Sendable, Equatable, Hashable {
    /// Number of distinct movement episodes (the device going from still to handled) within the window.
    let pickups: Int
    /// Total time the device was moving during the window, in seconds.
    let movingDuration: TimeInterval

    /// An undisturbed night — the device was still the whole window. Recorded (we *had* motion data),
    /// distinct from `nil` (no motion data at all → unavailable, not fabricated).
    static let none = SleepDisturbances(pickups: 0, movingDuration: 0)
}

/// Port for a **retroactive** motion-activity history query (WG-310). The real adapter
/// (`MotionInfrastructure`) runs a bounded, foreground-only `CMMotionActivityManager` history query — **no
/// background execution, no continuous sensing** — and returns the classified segments; the domain stays
/// framework-independent. A denied/unavailable source throws, so the consumer degrades to "no estimate"
/// rather than reading silence as "undisturbed".
protocol MotionActivityHistorySource: Sendable {
    func activitySamples(in window: DateInterval) async throws -> [MotionActivitySample]
}

/// Estimates overnight disturbances from a window of historical motion-activity samples (WG-310). Pure and
/// deterministic. Each sample classifies the span until the next sample; a **disturbance episode** is a
/// maximal run of *moving* spans, and moving time is their total. `.stationary` and `.unknown` are **not**
/// disturbances — `.unknown` is an unconfident classification, so counting it would over-report; the
/// estimator deliberately **under-counts** (a missed disturbance is harmless; a false "you were disturbed"
/// is not).
enum SleepDisturbanceEstimator {
    /// Kinds that mean the device was genuinely handled/moving — everything else (still, unknown) is quiet.
    static let movingKinds: Set<MotionActivityKind> = [
        .walking, .running, .cycling, .automotive,
    ]

    /// The local wall-clock hour that bounds how far back a "night" may begin (WG-313). Anchoring to an
    /// **evening** rather than a rolling lookback is what makes the estimate stable: the candidate span no
    /// longer slides forward every time the readiness screen is opened.
    static let nightAnchorHour = 18

    /// A moving run shorter than this is a **disturbance inside** the night, not the end of it (WG-313).
    /// Without this merge a single 2 a.m. bathroom trip would split the night in two, and the "night"
    /// would become whichever half happened to be longer.
    static let maxDisturbanceGap: TimeInterval = 20 * 60

    /// The shortest quiet block that may be called a night (WG-313). Below this we report **unavailable**
    /// rather than dressing up a brief lull as a night — a phone set down for twenty minutes is not sleep.
    static let minimumNightDuration: TimeInterval = 90 * 60

    /// The span to search for last night's rest, `[previous local 18:00, now]` (WG-313). Anchored to a
    /// **local wall-clock** evening through the injected calendar, so a DST transition shifts the anchor
    /// with the clock while every duration stays absolute elapsed time. Always the *previous* local day, so
    /// the most recently completed night stays reachable all day rather than vanishing each evening. Well
    /// inside CoreMotion's ~7-day history retention.
    static func candidateSpan(endingAt now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let previousDay =
            calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)
        let anchor =
            calendar.date(bySettingHour: nightAnchorHour, minute: 0, second: 0, of: previousDay)
            ?? previousDay
        return DateInterval(start: min(anchor, now), end: now)
    }

    /// The night **within** `span`, derived from the samples rather than the clock (WG-313): quiet runs are
    /// merged across moving runs shorter than `maxDisturbanceGap`, and the longest merged block is the
    /// night — bookended by settling down and getting up. `nil` when no block reaches
    /// `minimumNightDuration` (unavailable, never fabricated).
    ///
    /// The night has to be the merged block, not a single quiet run: counting disturbances inside one quiet
    /// run would always yield zero, because a quiet run is non-moving by construction.
    ///
    /// **Known defect (WG-313 H2), not fixed.** Ranking by raw duration lets a sedentary *day* outrank the
    /// night: a desk-bound workday reports the desk as the night, and while that block is still open it
    /// grows every hour the screen is opened. Pinned as expected failures by
    /// `testSedentaryDaytimeBlockDoesNotOutrankTheNight` (open block) and
    /// `testClosedSedentaryDaytimeBlockStillOutranksABrokenNight` (a block the data closes, which reports
    /// **zero** disturbances for a broken night). Two fixes have been implemented and reverted — a
    /// wall-clock night band, and H3's trailing validity cap — see the WG-313 ADR before attempting a
    /// third; both traded a common mild error for a rare severe one.
    static func nightSpan(samples: [MotionActivitySample], in span: DateInterval) -> DateInterval? {
        var blocks: [DateInterval] = []
        var blockStart: Date?
        var blockEnd: Date?
        // Movement is judged over a contiguous **run**, not one sample's span — the same maximal-run
        // definition `estimate` uses. Judging spans individually let a fragmented morning (a short walk,
        // sitting, another short walk) hold the night open indefinitely, because no single span reached
        // `maxDisturbanceGap`: the drift this task exists to remove, one layer down.
        var movingRun: TimeInterval = 0
        for classified in classifiedSpans(samples: samples, window: span) {
            if classified.isMoving {
                movingRun += classified.interval.duration
                // A brief disturbance leaves the block open; a sustained run ends the night.
                guard movingRun >= maxDisturbanceGap, let start = blockStart, let end = blockEnd
                else { continue }
                blocks.append(DateInterval(start: start, end: end))
                blockStart = nil
                blockEnd = nil
            } else {
                movingRun = 0
                if blockStart == nil { blockStart = classified.interval.start }
                blockEnd = classified.interval.end
            }
        }
        if let start = blockStart, let end = blockEnd {
            blocks.append(DateInterval(start: start, end: end))
        }
        guard let longest = blocks.max(by: { $0.duration < $1.duration }),
            longest.duration >= minimumNightDuration
        else { return nil }
        return longest
    }

    /// One span of the timeline: the interval a sample covers, clipped to the window, and whether the
    /// device was moving during it. Each sample classifies the span until the next sample.
    private struct ClassifiedSpan {
        let interval: DateInterval
        let isMoving: Bool
    }

    /// The window's timeline as non-overlapping classified spans, in order. Spans outside the window
    /// collapse to nothing and are dropped, so an empty result means **no data** for the window.
    ///
    /// **Known defect (WG-313 H3), not fixed.** A sample classifies the timeline until the next sample, and
    /// the last sample classifies everything up to `window.end`. Silence is therefore read as stillness, so
    /// one stale `.stationary` record — or an explicitly unconfident `.unknown` — fabricates a night, and a
    /// device that was powered off overnight reports a fifteen-hour one. A **trailing-only** validity cap
    /// was implemented and **reverted** — see the WG-313 ADR; it left the interior-gap fabrication
    /// untouched while shrinking unclosed real nights, so a sofa outranked the bed and a sleeper who opened
    /// the app before their first step lost the section entirely.
    private static func classifiedSpans(samples: [MotionActivitySample], window: DateInterval)
        -> [ClassifiedSpan]
    {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        var spans: [ClassifiedSpan] = []
        for (index, sample) in sorted.enumerated() {
            let rawEnd = index + 1 < sorted.count ? sorted[index + 1].timestamp : window.end
            let start = max(sample.timestamp, window.start)
            let end = min(rawEnd, window.end)
            guard end > start else { continue }
            spans.append(
                ClassifiedSpan(
                    interval: DateInterval(start: start, end: end),
                    isMoving: movingKinds.contains(sample.kind)))
        }
        return spans
    }

    /// Estimate disturbances within `window`. `nil` when no sample overlaps the window (no motion data →
    /// unavailable); a genuinely still night is `.none` (0 pickups), never conflated with unavailable.
    static func estimate(samples: [MotionActivitySample], window: DateInterval)
        -> SleepDisturbances?
    {
        let spans = classifiedSpans(samples: samples, window: window)
        guard !spans.isEmpty else { return nil }
        var pickups = 0
        var movingDuration: TimeInterval = 0
        var inEpisode = false
        for span in spans {
            if span.isMoving {
                if !inEpisode { pickups += 1 }
                inEpisode = true
                movingDuration += span.interval.duration
            } else {
                inEpisode = false
            }
        }
        return SleepDisturbances(pickups: pickups, movingDuration: movingDuration)
    }

    /// The longest contiguous **low-activity** (non-moving) stretch within the window (WG-311), in seconds
    /// — a coarse "rest window" estimate for users without measured sleep. Emphatically **not sleep** and
    /// **not a readiness factor**: a still phone is not a sleeping person (it may sit on a desk for hours),
    /// so the UI shows this only as a clearly-labelled, supplemental estimate and never folds it into the
    /// grounded readiness score. A span is "quiet" when its kind is not a `movingKind` (so `.stationary`
    /// and the frequent low-confidence `.unknown` both count), mirroring `estimate`'s moving/not split.
    /// `nil` when no sample overlaps the window (unavailable, not fabricated).
    static func longestRestWindow(samples: [MotionActivitySample], window: DateInterval)
        -> TimeInterval?
    {
        let spans = classifiedSpans(samples: samples, window: window)
        guard !spans.isEmpty else { return nil }
        var longest: TimeInterval = 0
        var current: TimeInterval = 0
        for span in spans {
            if span.isMoving {
                current = 0
            } else {
                current += span.interval.duration
                longest = max(longest, current)
            }
        }
        return longest
    }
}
