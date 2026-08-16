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

    /// A coarse overnight lookback — a groggy user opens readiness in the morning, so "last night" is the
    /// several hours before now. Ample without scanning unbounded history.
    static let defaultOvernightLookback: TimeInterval = 10 * 3_600

    /// The window to estimate over: `[now - lookback, now]`. Foreground, recent — well inside CoreMotion's
    /// ~7-day history retention.
    static func overnightWindow(
        endingAt now: Date, lookback: TimeInterval = defaultOvernightLookback
    ) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-max(0, lookback)), end: now)
    }

    /// Estimate disturbances within `window`. `nil` when no sample overlaps the window (no motion data →
    /// unavailable); a genuinely still night is `.none` (0 pickups), never conflated with unavailable.
    static func estimate(samples: [MotionActivitySample], window: DateInterval)
        -> SleepDisturbances?
    {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        var pickups = 0
        var movingDuration: TimeInterval = 0
        var inEpisode = false
        var sawData = false
        for (index, sample) in sorted.enumerated() {
            let rawEnd = index + 1 < sorted.count ? sorted[index + 1].timestamp : window.end
            let start = max(sample.timestamp, window.start)
            let end = min(rawEnd, window.end)
            guard end > start else { continue }
            sawData = true
            if movingKinds.contains(sample.kind) {
                if !inEpisode { pickups += 1 }
                inEpisode = true
                movingDuration += end.timeIntervalSince(start)
            } else {
                inEpisode = false
            }
        }
        guard sawData else { return nil }
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
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        var longest: TimeInterval = 0
        var current: TimeInterval = 0
        var sawData = false
        for (index, sample) in sorted.enumerated() {
            let rawEnd = index + 1 < sorted.count ? sorted[index + 1].timestamp : window.end
            let start = max(sample.timestamp, window.start)
            let end = min(rawEnd, window.end)
            guard end > start else { continue }
            sawData = true
            if movingKinds.contains(sample.kind) {
                current = 0
            } else {
                current += end.timeIntervalSince(start)
                longest = max(longest, current)
            }
        }
        return sawData ? longest : nil
    }
}
