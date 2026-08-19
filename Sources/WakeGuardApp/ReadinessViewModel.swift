import Foundation
import Observation

/// Drives the readiness card (WG-130): queries recent sleep, computes the assessment, and holds it for the
/// UI. Degrades safely across every HealthKit access state — a **denied / revoked / errored** query
/// returns no samples (or throws), which yields an assessment with **no factors** ("not enough data"),
/// never a crash. It is **recomputed on every refresh**, so a revocation replaces any prior value and
/// **no stale readiness claim remains**. `@MainActor` because it feeds SwiftUI directly; holds no alarm
/// authority.
@MainActor
@Observable
final class ReadinessViewModel {
    /// The current readiness, or `nil` before the first refresh. After a refresh it always reflects the
    /// **current** data — an unavailable one has no factors.
    private(set) var assessment: ReadinessAssessment?

    /// Last night's mid-sleep interruptions (WG-309), or `nil` when there is no sleep data. Recomputed on
    /// every refresh from the same samples, so it never outlives a revoked grant.
    private(set) var lastNightInterruptions: SleepInterruptions?

    /// The whole state of the "Movement overnight" section (WG-310/311/312/318) — shown **always**
    /// (alongside any HealthKit sleep data, WG-312), not only as a fallback. One total value, so "no
    /// estimate and no reason", which renders as the section silently vanishing, is not representable.
    ///
    /// Starts at `.loading`, which is the honest description of a cold open: the card is already on screen
    /// by the time the motion query starts.
    private(set) var movement: MovementDisplayState = .loading

    /// A motion-based **estimate** of overnight disturbances, or `nil` when there is none to show.
    /// Derived from `movement` rather than stored alongside it — as two independent optionals, nothing but
    /// a doc comment kept the estimate and the reason consistent, and they could both end up `nil`.
    var estimatedDisturbances: SleepDisturbances? {
        guard case .available(let disturbances, _) = movement else { return nil }
        return disturbances
    }

    /// A motion-based **estimate** of the longest low-activity (rest) stretch overnight (WG-311), in
    /// seconds. **Not sleep and not a readiness factor** (a still phone isn't a sleeping person); shown only
    /// as a clearly-labelled estimate. It comes from the same query and the same night as
    /// `estimatedDisturbances`, so the two are present or absent together — now by construction.
    var estimatedRest: TimeInterval? {
        guard case .available(_, let rest) = movement else { return nil }
        return rest
    }

    /// **Why** there is no movement estimate to show, or `nil` when there is one (WG-318). The estimate
    /// going `nil` used to be the only signal, so "this device can't track movement", "Motion access is off"
    /// and "not enough data to call it a night" were indistinguishable and the section simply vanished — the
    /// user was told nothing. `nil` while `.loading`: no reason is known yet, and reporting one would be a
    /// guess.
    var movementUnavailability: MovementUnavailability? {
        guard case .unavailable(let reason) = movement else { return nil }
        return reason
    }

    /// Orders overlapping refreshes. `async` gives no completion-ordering guarantee, so without this the
    /// answer that finishes *last* wins — including a stale failure replacing a fresh estimate with a
    /// permission complaint while access is in fact granted.
    ///
    /// Claimed at the very top of `refresh(now:)`, **before any `await`**: claiming it after the sleep
    /// query would order motion queries by which refresh's *HealthKit* read happened to return first, which
    /// is not the same as which refresh started, and would let an older `now` (hence an older candidate
    /// span) win.
    ///
    /// Today this is defensive — `ReadinessScreen` has no `.refreshable` and no scene-phase hook, so its
    /// single `.task` cannot normally overlap itself. It becomes load-bearing the moment either is added.
    private var movementGeneration = 0

    /// The generation whose result is currently on screen. Compared with `>` rather than `==` so a
    /// *cancelled* newest refresh cannot starve an older one that actually produced an answer: cancellation
    /// is not a result, so it must not claim this.
    private var appliedMovementGeneration = 0

    private let sleepQuery: any SleepSampleQuerying
    private let motionHistory: (any MotionActivityHistorySource)?
    private let need: SleepNeed
    private let calendar: Calendar
    private let lookback: TimeInterval
    private let movementTimeout: Duration

    init(
        sleepQuery: any SleepSampleQuerying,
        motionHistory: (any MotionActivityHistorySource)? = nil, need: SleepNeed = .default,
        calendar: Calendar = Calendar(identifier: .gregorian), lookback: TimeInterval = 14 * 86_400,
        movementTimeout: Duration = .seconds(15)
    ) {
        self.sleepQuery = sleepQuery
        self.motionHistory = motionHistory
        self.need = need
        self.calendar = calendar
        self.lookback = lookback
        self.movementTimeout = movementTimeout
    }

    /// Recompute readiness from the current data. Never throws or crashes: a denied/revoked/errored query
    /// degrades to an unavailable ("not enough data") assessment, replacing any prior value.
    func refresh(now: Date) async {
        movementGeneration += 1
        let generation = movementGeneration
        let samples =
            (try? await sleepQuery.sleepSamples(from: now.addingTimeInterval(-lookback), to: now))
            ?? []
        assessment = ReadinessComputer.readiness(from: samples, need: need, calendar: calendar)
        lastNightInterruptions = ReadinessComputer.lastNightInterruptions(from: samples)
        await applyMovementSummary(now: now, generation: generation)
    }

    /// The always-on movement summary (WG-310/311/312/318): whenever a motion source is wired, one query
    /// populates **both** the disturbance and rest estimates — shown alongside any HealthKit sleep data, no
    /// longer gated on HealthKit being empty — or else says why it can't (WG-318), never a fabricated value.
    ///
    /// The screen changes **once**, at the end, from one total `MovementSummary`. Assigning as it went meant
    /// a populated section was blanked for the duration of every query, and left an estimate and a reason as
    /// two independent optionals that could both end up `nil`.
    private func applyMovementSummary(now: Date, generation: Int) async {
        let summary = await summaryBeforeDeadline(now: now)
        // A refresh that already applied a result was newer than this one, so this answer is stale.
        // `@MainActor` makes the compare-and-set race-free without a lock.
        guard generation > appliedMovementGeneration else { return }
        switch summary {
        case .available(let disturbances, let rest):
            appliedMovementGeneration = generation
            movement = .available(disturbances, rest: rest)
        case .unavailable(let reason):
            appliedMovementGeneration = generation
            movement = .unavailable(reason)
        case .cancelled, .timedOut:
            // Neither is a result. Whatever is on screen was true a moment ago and is still the
            // best answer available; replacing it would blank the section to say nothing.
            //
            // Except on a cold open, where there is nothing to preserve: leaving `.loading` would show a
            // spinner with **no query in flight and none scheduled** — a permanent "working on it" that is
            // simply false, and the vanished section of WG-318 wearing a different costume. Nothing was
            // read, so "we couldn't read it just now" is the honest terminal state. Whether today's view
            // tree can actually reach this is an accident of having no `.refreshable`; the same reasoning
            // that hardened the generation guard applies here.
            // `generation == movementGeneration` as well: a *newer* refresh may still be in flight, and
            // writing a failure for a read that is currently running claims something we don't know. The
            // cold-open fallback is only honest when this cancelled refresh is also the latest one. If that
            // newest refresh is itself the cancelled one the clause holds, so the spinner still can't stick.
            guard case .loading = movement, generation == movementGeneration else { break }
            movement = .unavailable(.temporarilyUnavailable)
        }
    }

    /// `movementSummary`, but bounded by `movementTimeout` (WG-318).
    ///
    /// A `CMMotionActivityManager` history query is a one-shot call whose completion handler carries no
    /// delivery guarantee. If it never fires, the read never returns, `movement` stays `.loading`, and —
    /// this screen having no `.refreshable` and no scene-phase hook — nothing re-runs the query for the life
    /// of the process. "Checking your movement…" forever is the vanished section of WG-318 in its last
    /// costume: a spinner is not an answer, and it is the one failure the user cannot tell from a slow read.
    ///
    /// The loser of the race is **abandoned, not awaited**. A structured `withThrowingTaskGroup` cancels its
    /// remaining children and then *waits for them* on scope exit, so against a source that does not honour
    /// cancellation — precisely the hung source this exists to survive — the deadline would be inert while
    /// looking correct. `testAQueryThatNeverAnswersDoesNotLeaveAPermanentSpinner` uses a double that ignores
    /// cancellation for that reason: it fails against the structured form.
    ///
    /// Abandoning leaks the in-flight read until CoreMotion releases it. A one-shot hardware query cannot be
    /// un-started, so the choice is only *who waits* — and a leaked read the user cannot see is strictly
    /// better than a spinner they can. `read.cancel()` still reclaims it promptly for any source that
    /// honours cancellation, which the real adapter now does.
    private func summaryBeforeDeadline(now: Date) async -> MovementSummary {
        let (outcomes, publish) = AsyncStream<MovementSummary>.makeStream()
        let read = Task { publish.yield(await self.movementSummary(now: now)) }
        let deadline = Task { [movementTimeout] in
            try await Task.sleep(for: movementTimeout)
            // Nothing came back, so this reports a *read* that failed. Not a permission or hardware claim:
            // the query got far enough to be waiting on the sensor, so we have no evidence for either, and
            // `.temporarilyUnavailable` is the one reason that asks the user to change nothing.
            //
            // Yielded as `.timedOut`, **not** as that `.unavailable` directly: an `.unavailable` is applied
            // unconditionally, so a timeout would erase a correct estimate that is still the best answer
            // available. `applyMovementSummary` maps this to the same reason once it has established there
            // is nothing to preserve.
            publish.yield(.timedOut)
        }
        defer {
            read.cancel()
            deadline.cancel()
        }
        for await first in outcomes { return first }
        // The stream ends without a winner only when *this* task was cancelled, which is not a result —
        // `.cancelled` keeps whatever was on screen rather than blanking it to say nothing.
        return .cancelled
    }

    /// Read motion history and reduce it to one summary. **Writes no state** — that is what lets the caller
    /// apply it atomically and drop it if it has been superseded.
    private func movementSummary(now: Date) async -> MovementSummary {
        guard let motionHistory else { return .unavailable(.sourceUnavailable) }
        let span = SleepDisturbanceEstimator.candidateSpan(endingAt: now, calendar: calendar)
        let samples: [MotionActivitySample]
        do {
            samples = try await motionHistory.activitySamples(in: span)
        } catch is CancellationError {
            // The refresh was cancelled and the screen is going away. Reachable **both** before the query
            // starts (the adapter's up-front `checkCancellation`) and mid-flight: the adapter's cancellation
            // handler now resumes immediately rather than waiting on a CoreMotion call it cannot stop.
            // This comment previously asserted the mid-flight case was unreachable — which is how a
            // dismissed screen came to leak a continuation, and its task, on every dismissal.
            return .cancelled
        } catch {
            return .unavailable(.from(error))
        }
        // The night is found in the samples, not measured back from the clock (WG-313) — so opening the
        // screen again later reports the same night instead of dropping its start and sweeping in the
        // morning's activity. Any of the three steps failing means we have no night to describe, which is
        // "not enough data", never a silently missing section.
        guard let night = SleepDisturbanceEstimator.nightSpan(samples: samples, in: span),
            let disturbances = SleepDisturbanceEstimator.estimate(samples: samples, window: night),
            let rest = SleepDisturbanceEstimator.longestRestWindow(samples: samples, window: night)
        else { return .unavailable(.noNightFound) }
        return .available(disturbances, rest: rest)
    }
}
