import Foundation

/// Which motion source a movement observation came from — provenance for merged multi-stream input.
enum MovementSource: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case pedometer
    case activity
    case deviceMotion
    case altitude
}

/// One framework-neutral movement observation on a shared timeline (WG-067) — the unit the episode
/// builder merges across sources. `isMoving` is the source's already-decided verdict (a walking
/// activity, a live pedometer step); `cumulativeSteps` is carried only by step sources, for
/// per-episode totals and reset detection.
struct MovementObservation: Sendable, Equatable {
    let timestamp: Date
    let isMoving: Bool
    let cumulativeSteps: Int?
    let source: MovementSource

    init(timestamp: Date, isMoving: Bool, cumulativeSteps: Int? = nil, source: MovementSource) {
        self.timestamp = timestamp
        self.isMoving = isMoving
        self.cumulativeSteps = cumulativeSteps
        self.source = source
    }
}

extension MovementObservation {
    // Only per-timestamp *movement* streams (pedometer, activity) become observations. A future
    // `from(altitude:)` / `from(deviceMotion:)` must NOT set `isMoving = true` from a lone altitude
    // or pickup signal — that is supporting-only evidence (WG-065/066); a barometric or device-motion
    // blip must never fabricate a movement episode.

    /// A live pedometer sample is itself movement — WG-063's stream only emits while stepping, so a
    /// stop is an emission gap the builder segments on. Carries the cumulative step count.
    static func from(pedometer sample: PedometerSample) -> MovementObservation {
        MovementObservation(
            timestamp: sample.timestamp, isMoving: true, cumulativeSteps: sample.stepCount,
            source: .pedometer)
    }

    /// An activity sample counts as movement only when the classifier is confident it's on-foot
    /// (walking / running); stationary / unknown are not movement and simply don't contribute.
    static func from(activity sample: MotionActivitySample) -> MovementObservation {
        MovementObservation(
            timestamp: sample.timestamp,
            isMoving: sample.kind == .walking || sample.kind == .running,
            source: .activity)
    }
}

/// A continuous stretch of movement on the merged timeline (WG-067): its bounds, an **advisory**
/// step total, and how many observations formed it. The consumer (WG-068/069) decides whether a
/// `duration` is a *sustained* walk (e.g. ≥ 10 s) — the builder only segments, it sets no such gate.
/// `observationCount` relative to `duration` is the mean inter-observation gap: a real walk is
/// **dense** (~1 s between samples) while a sparse injected/replayed "episode" (one sample per
/// pause-gap) is not, so WG-069 can reject a fabricated sustained episode from these two fields
/// without re-deriving the timeline.
struct MovementEpisode: Sendable, Equatable, Hashable {
    let start: Date
    let end: Date
    /// Advisory best-effort step total — reset-safe against inflation, but **not** an anti-cheat
    /// gate (see `MovementEpisodeBuilder.steps(in:)`). Duration + density are the gate.
    let stepCount: Int
    let observationCount: Int

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Merges timestamped movement observations from multiple sources into continuous movement episodes
/// (WG-067), handling out-of-order/stale/future samples, pauses, and cumulative-counter resets. Pure
/// and deterministic — the challenge runtime supplies the observations and `now`.
enum MovementEpisodeBuilder {

    /// Tunable segmentation config. Cautious defaults; on-device calibration is deferred to the
    /// challenge (WG-068/069).
    struct Config: Sendable, Equatable {
        /// A gap between consecutive moving observations larger than this ends an episode (a pause).
        var pauseGap: TimeInterval
        /// Observations older than `now - staleHorizon` are stale for a real-time "moving now"
        /// judgment and are dropped (the WG-064 stale-timestamp handoff lands here).
        var staleHorizon: TimeInterval
        /// Observations later than `now + maxFutureSkew` are implausible and dropped.
        var maxFutureSkew: TimeInterval
        /// An episode needs at least this many observations — fewer is noise (a single stray toss),
        /// not a movement episode.
        var minEpisodeObservations: Int

        static let `default` = Config(
            pauseGap: 3, staleHorizon: 60, maxFutureSkew: 5, minEpisodeObservations: 2)
    }

    /// Build episodes from one or more observation streams, merged by timestamp.
    static func build(
        merging streams: [[MovementObservation]], now: Date, config: Config = .default
    ) -> [MovementEpisode] {
        // A non-finite clock would make the stale/future bounds NaN, and `Date`'s NaN-blind
        // comparisons would then let *every* observation pass — silently disarming this freshness
        // gate (WG-067 review B1). Fail closed: with no trustworthy clock there is no fresh episode.
        guard now.timeIntervalSince1970.isFinite else { return [] }
        let earliest = now.addingTimeInterval(-config.staleHorizon)
        let latest = now.addingTimeInterval(config.maxFutureSkew)

        // Merge every stream onto one timeline: keep only fresh, finite, actually-moving
        // observations, then order by time. Dropping stale/future/out-of-order here is the single
        // freshness gate the sensor adapters deliberately deferred (WG-064/066).
        let moving =
            streams
            .flatMap { $0 }
            .filter {
                $0.isMoving && $0.timestamp.timeIntervalSince1970.isFinite
                    && $0.timestamp >= earliest && $0.timestamp <= latest
            }
            .sorted { $0.timestamp < $1.timestamp }

        var episodes: [MovementEpisode] = []
        var current: [MovementObservation] = []

        func flush() {
            defer { current = [] }
            guard current.count >= config.minEpisodeObservations, let first = current.first,
                let last = current.last
            else { return }
            episodes.append(
                MovementEpisode(
                    start: first.timestamp, end: last.timestamp,
                    stepCount: Self.steps(in: current), observationCount: current.count))
        }

        for observation in moving {
            if let previous = current.last,
                observation.timestamp.timeIntervalSince(previous.timestamp) > config.pauseGap
            {
                flush()
            }
            current.append(observation)
        }
        flush()
        return episodes
    }

    /// Convenience for a single already-merged stream.
    static func build(
        from observations: [MovementObservation], now: Date, config: Config = .default
    ) -> [MovementEpisode] {
        build(merging: [observations], now: now, config: config)
    }

    /// Steps accrued across an episode's step observations — **reset-safe against inflation**. A
    /// cumulative decrease (a reset / glitch) *freezes* accounting at the pre-reset run rather than
    /// re-adding a fresh climb from the reset baseline, so no interleaving of resets can inflate the
    /// total (a single monotonic run is the most it can report). Advisory only: `duration` and the
    /// observation density, **not** this count, are the anti-cheat gate (WG-069/070).
    static func steps(in observations: [MovementObservation]) -> Int {
        var total = 0
        var lastCumulative: Int?
        for steps in observations.compactMap(\.cumulativeSteps) {
            guard let last = lastCumulative else {
                lastCumulative = steps
                continue
            }
            if steps < last { break }  // a reset ends accounting — never re-add a climb across it
            total += steps - last
            lastCumulative = steps
        }
        return total
    }
}
