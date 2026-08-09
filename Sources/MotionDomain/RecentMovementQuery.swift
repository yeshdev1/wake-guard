import Foundation

/// A bounded, on-demand snapshot of recent movement (WG-081): how many steps occurred in a bounded
/// recent window and an upper bound on how long ago the last movement was. It is produced by querying
/// the historical pedometer on demand — there is **no continuous overnight sensing** — and every
/// window is bounded, so a query can never read the future or an unbounded range. Advisory only: the
/// snapshot is a plain value with no alarm authority, so recent-movement evidence can never by itself
/// suppress an alarm (#8).
///
/// The step total is an aggregate of the historical pedometer's `.high`-quality readings; per-sample
/// quality is intentionally collapsed here because CMPedometer history is authoritative (WG-062) —
/// quality-weighting is out of scope for the historical path (recorded in the WG-081 ADR).
struct RecentMovementSnapshot: Sendable, Equatable {
    /// The widest bounded window queried; `nil` when no query ran — i.e. the clock was unusable or
    /// the ladder had no valid rung (both fail-closed).
    let window: PedometerQueryWindow?
    /// Steps observed in the widest window (saturating sum; historical samples are
    /// absolute-for-their-window, not cumulative-since-boot).
    let stepCount: Int
    /// An upper bound on the seconds since the last movement — the tightest recency rung that still
    /// contained a step; `.infinity` when no movement was observed. Coarse by construction: aggregate
    /// pedometer history reveals a per-window count (stamped at the window end), not a precise
    /// last-step time, so recency is quantized to the ladder's rungs (pinned as a known limitation).
    let secondsSinceLastMovement: TimeInterval
    /// Whether the pedometer was available to observe. When `false`, `stepCount == 0` means
    /// **"couldn't observe"**, not "confirmed still" — a safety-sensitive consumer (WG-082) must
    /// treat the two differently even though both keep the alarm (#8).
    let sourceAvailable: Bool

    static let empty = RecentMovementSnapshot(
        window: nil, stepCount: 0, secondsSinceLastMovement: .infinity, sourceAvailable: false)

    /// Whether any movement was observed **within the widest window** — not necessarily *recent*
    /// (consult `secondsSinceLastMovement`); "moved in the last N minutes", not "moving now".
    var movementDetected: Bool { stepCount > 0 }
}

/// Queries recent movement from the historical (bounded-window) pedometer (WG-081) — the E05
/// pre-alarm feeder. It issues one availability check plus a small ladder of **bounded, on-demand**
/// queries (never a stream, so no continuous overnight sensing) and reports the recent step count
/// plus a recency upper bound. Fail-closed throughout: a non-finite clock, an unavailable source, or
/// a query error yields a no-movement snapshot, never a fabricated "just moved". Clock changes and
/// stale samples are handled — each window is validated against the *current* `now`, and any sample
/// outside the queried window (a backward / forward clock jump, a future / stale timestamp) is
/// dropped. Pure of clock reads: `now` is injected. Advisory only — the snapshot has no alarm
/// authority (#8).
struct RecentMovementQuery: Sendable {

    struct Config: Sendable, Equatable {
        /// The recency ladder (look-backs, seconds). The tightest rung still containing a step sets
        /// the recency bound; the widest bounds the step count. Each rung is one bounded query.
        var recencyLadderSeconds: [TimeInterval]

        static let `default` = Config(recencyLadderSeconds: [180, 600, 1800])
    }

    /// A defensive cap on the number of distinct rungs, so a pathological config can't fan out into
    /// unbounded I/O (bounded cost). The widest rungs are kept (the widest sets the step count).
    static let maxLadderRungs = 8

    let source: HistoricalPedometerSource
    var config: Config = .default

    /// Snapshot recent movement as of `now`. Issues one `availability()` check and then at most
    /// `recencyLadderSeconds.count` bounded queries — only one when no movement is present.
    func snapshot(now: Date) async -> RecentMovementSnapshot {
        guard now.timeIntervalSince1970.isFinite else { return .empty }
        let rungs = sanitizedLadder()
        guard let widest = rungs.last, let wideWindow = makeWindow(span: widest, now: now) else {
            return .empty
        }
        guard await source.availability() == .available else {
            // Couldn't observe — distinct from "confirmed still" (sourceAvailable == false).
            return RecentMovementSnapshot(
                window: wideWindow, stepCount: 0, secondsSinceLastMovement: .infinity,
                sourceAvailable: false)
        }
        let wideSteps = await stepCount(in: wideWindow)
        guard wideSteps > 0 else {
            return RecentMovementSnapshot(
                window: wideWindow, stepCount: 0, secondsSinceLastMovement: .infinity,
                sourceAvailable: true)
        }
        let recency = await tightenedRecency(rungs: rungs, widest: widest, now: now)
        return RecentMovementSnapshot(
            window: wideWindow, stepCount: wideSteps, secondsSinceLastMovement: recency,
            sourceAvailable: true)
    }

    /// Tighten the recency bound to the smallest rung that still contains a step. Cancellation
    /// abandons tightening and yields the honest widest upper bound rather than issuing wasted
    /// queries (and never a spuriously *looser* value from a swallowed cancellation mid-rung).
    private func tightenedRecency(rungs: [TimeInterval], widest: TimeInterval, now: Date) async
        -> TimeInterval
    {
        for span in rungs.dropLast() {
            if Task.isCancelled { break }
            guard let window = makeWindow(span: span, now: now) else { continue }
            if await stepCount(in: window) > 0 { return span }
        }
        return widest
    }

    private func sanitizedLadder() -> [TimeInterval] {
        let cleaned =
            config.recencyLadderSeconds
            .filter { $0.isFinite && $0 > 0 }
            .map { min($0, PedometerQueryWindow.maxSpan) }
        return Array(Set(cleaned)).sorted().suffix(Self.maxLadderRungs).map { $0 }
    }

    private func makeWindow(span: TimeInterval, now: Date) -> PedometerQueryWindow? {
        try? PedometerQueryWindow(start: now.addingTimeInterval(-span), end: now, now: now)
    }

    /// Steps in a window, fail-closed: an unavailable / throwing source counts as zero, and any
    /// sample outside `[start, end]` or non-finite / non-positive is dropped. This re-check against
    /// the *current* `now`-derived window is **deliberately redundant** with the adapter's own
    /// `PedometerSample.validated` — do not "DRY" it away: it is what closes the clock-jump hole (a
    /// sample validated against its original window is re-tested here against the new one) and it
    /// guards fakes that bypass `validated`. Historical samples are absolute-for-their-window, so the
    /// window total is their saturating sum — overflow saturates rather than trapping (WG-080/068).
    private func stepCount(in window: PedometerQueryWindow) async -> Int {
        guard let samples = try? await source.samples(in: window) else { return 0 }
        return samples.reduce(0) { accumulated, sample in
            guard sample.timestamp.timeIntervalSince1970.isFinite,
                sample.timestamp >= window.start, sample.timestamp <= window.end,
                sample.stepCount > 0
            else { return accumulated }
            let (sum, overflow) = accumulated.addingReportingOverflow(sample.stepCount)
            return overflow ? Int.max : sum
        }
    }
}
