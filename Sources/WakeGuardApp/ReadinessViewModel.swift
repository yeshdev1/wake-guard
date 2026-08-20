import Foundation
import Observation

/// Drives the readiness card (WG-130): queries recent sleep, computes the assessment, and holds it for the
/// UI. Degrades safely across every HealthKit access state — a **denied or revoked** grant returns no
/// samples (HealthKit does not reveal read denial), which yields an assessment with **no factors** ("not
/// enough data"), never a crash. It is **recomputed on every refresh**, so a revocation replaces any prior
/// value and **no stale readiness claim remains**.
///
/// A read that **errored, timed out or was cancelled** is handled separately and does *not* yield that
/// assessment: nothing was read, so there is no basis for a claim about the user's data (WG-319). It
/// reports the failed read instead, and preserves a correct assessment rather than replacing it.
/// `@MainActor` because it feeds SwiftUI directly; holds no alarm authority.
@MainActor
@Observable
final class ReadinessViewModel {
    /// The whole state of the readiness explanation (WG-319): still loading, an assessment, or why there
    /// isn't one. One total value, so "no assessment and no reason" — which the card resolved by claiming a
    /// data shortage the query never established — is not representable.
    ///
    /// Starts at `.loading`, which is the honest description of a cold open: the query is genuinely in
    /// flight, and the screen's spinner is true for exactly as long as this case holds.
    private(set) var readiness: ReadinessDisplayState = .loading

    /// The current readiness, or `nil` when there is none to show. **Derived** from `readiness` rather than
    /// stored alongside it — as an independent optional it carried two meanings ("not read yet" and "read,
    /// nothing there") that the card could not tell apart, which is the WG-319 defect itself.
    var assessment: ReadinessAssessment? {
        guard case .assessed(let assessment) = readiness else { return nil }
        return assessment
    }

    /// **Why** there is no readiness to show, or `nil` when there is one. Derived for the same reason as
    /// `assessment`, and the mirror of `movementUnavailability` one layer up.
    var readinessUnavailability: ReadinessUnavailability? {
        guard case .unavailable(let reason) = readiness else { return nil }
        return reason
    }

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
    private let sleepTimeout: Duration

    init(
        sleepQuery: any SleepSampleQuerying,
        motionHistory: (any MotionActivityHistorySource)? = nil, need: SleepNeed = .default,
        calendar: Calendar = Calendar(identifier: .gregorian), lookback: TimeInterval = 14 * 86_400,
        movementTimeout: Duration = .seconds(15), sleepTimeout: Duration = .seconds(15)
    ) {
        self.sleepQuery = sleepQuery
        self.motionHistory = motionHistory
        self.need = need
        self.calendar = calendar
        self.lookback = lookback
        self.movementTimeout = movementTimeout
        self.sleepTimeout = sleepTimeout
    }

    /// Recompute readiness from the current data. Never throws or crashes.
    ///
    /// The two degrades are **different since WG-319**, and this comment previously ran them together. A
    /// denied or revoked grant returns an empty sample set (HealthKit does not reveal read denial), which
    /// yields a no-factors "not enough data" assessment and replaces any prior value. A query that **errored,
    /// timed out or was cancelled** read nothing, so it yields `.unavailable` instead and preserves a good
    /// assessment rather than replacing it.
    ///
    /// **The two reads are serial, so the deadlines compose by addition, not in parallel.** The sleep read is
    /// awaited to completion before the motion query starts: the card resolves within `sleepTimeout` (15s) and
    /// the movement section inside it within a further `movementTimeout` (15s), so **this method returns
    /// within 30s**, not the 15s either constant suggests on its own. Serial is deliberate — the card must be
    /// on screen before the movement section can be seen loading inside it, which is WG-318's cold-open fix.
    ///
    /// **That is a bound on `refresh`, not on the screen**, and an earlier version of this comment stated it
    /// as the latter. `ReadinessScreen`'s `.task` awaits an **unbounded** `requestAccess()` before calling
    /// this, so the reader's worst case is that wait plus these 30s. WG-319 scoped `requestAccess()` out
    /// deliberately (it blocks on a modal sheet the user is looking at, so the spinner behind it is not a
    /// falsehood they can see) — but scoped out is not bounded, and the composed number is what
    /// `SMK-16`/`SMK-17` should be read against.
    func refresh(now: Date) async {
        movementGeneration += 1
        let generation = movementGeneration
        applySleepRead(await samplesBeforeDeadline(now: now))
        await applyMovementSummary(now: now, generation: generation)
    }

    /// Apply one sleep read to the card (WG-319).
    ///
    /// A **concluded** read replaces whatever was on screen, failure included — that is what keeps a revoked
    /// grant from leaving a stale readiness claim behind, which this type's own docstring promises.
    ///
    /// A read that returned **nothing** — cancelled, timed out, or thrown — is not a result and must not
    /// overwrite a correct assessment with a worse one.
    ///
    /// The exception is the cold open: while `readiness` is still `.loading` the screen renders
    /// `ProgressView("Checking your sleep readiness…")` and nothing re-runs the query, so preserving "no
    /// answer yet" *is* the permanent spinner. It resolves to `.unavailable(.temporarilyUnavailable)`, which
    /// reports the **read**. It must not resolve to a no-factors assessment: that renders "There isn't enough
    /// sleep data yet", "Add a few nights of sleep data…" and a list naming every factor as absent — three
    /// claims about data the query never looked at, told to a user who may have fourteen nights of it.
    /// Reusing a string written for "the store is empty" to mean "we did not look" is how a false claim ships
    /// without anyone writing a false sentence.
    ///
    /// **What the `.loading` test does and does not buy.** It is order-independent for the *failure* cases:
    /// once any read has concluded, a nothing-was-read outcome can never displace it, whichever order the two
    /// land in. That is the whole of what this needs a guard for today.
    ///
    /// It buys nothing for `.samples`, which assigns **unconditionally** — so if two refreshes overlap, the
    /// one that *concludes* last wins even if it started first, and an older read can overwrite a newer one.
    /// (An earlier version of this comment claimed the opposite, that "whichever concludes first wins".)
    /// Deliberately left unguarded: `movementGeneration` exists because the movement path had a demonstrated
    /// ordering defect, and this one is unreachable while `ReadinessScreen` has no `.refreshable` and no
    /// scene-phase hook — its single `.task` cannot overlap itself. Adding a second generation counter here
    /// would add the mechanism that already misfired once on this branch (a guard that starved a cancelled
    /// newest refresh) for a case nothing can reach. **It becomes load-bearing the moment either affordance
    /// is added**, at which point this is the fix, not a comment.
    private func applySleepRead(_ outcome: SleepReadOutcome) {
        switch outcome {
        case .samples(let samples):
            readiness = .assessed(
                ReadinessComputer.readiness(from: samples, need: need, calendar: calendar))
            lastNightInterruptions = ReadinessComputer.lastNightInterruptions(from: samples)
        case .failed, .cancelled, .timedOut:
            guard case .loading = readiness else { break }
            readiness = .unavailable(.temporarilyUnavailable)
            lastNightInterruptions = nil
        }
    }

    /// The sleep read, bounded by `sleepTimeout` (WG-319).
    ///
    /// `HealthKitSleepQueryAdapter` awaits an `HKSampleQuery` completion handler through a continuation, and
    /// that handler carries no delivery guarantee. If it never fires, `assessment` stays `nil` and the card
    /// never renders — and this screen has no `.refreshable` and no scene-phase hook, so nothing re-runs the
    /// query **for as long as the reader stays on it**. The only escape is to navigate back and push the
    /// screen again, which rebuilds `ReadinessScreenContent`'s `@State` model and re-runs `.task`; the screen
    /// never offers that and the reader has no reason to guess it. That is the same defect WG-318 bounded for
    /// the *section*, one layer up and hiding strictly more: the whole card, including the always-on movement
    /// section.
    private func samplesBeforeDeadline(now: Date) async -> SleepReadOutcome {
        await firstResult(
            of: { await self.readSamples(now: now) }, orAfter: sleepTimeout, yielding: .timedOut)
            ?? .cancelled
    }

    /// One sleep read, reduced to an outcome. Only an **answer** is a result: a returned sample set, empty
    /// included, is the user's data as HealthKit reports it.
    ///
    /// Every throw means nothing was read. A cancellation obviously so; a query error equally, because it
    /// tells us about the read and nothing about the sleep. Neither is where a **revoked grant** arrives —
    /// HealthKit does not reveal read denial, so an unauthorized read comes back as `.samples([])` and
    /// replaces any stale readiness through that path, which is the guarantee this type's docstring makes.
    ///
    /// `try?` previously erased the cancellation distinction, so a cancelled refresh reported the user's data
    /// as absent; mapping the remaining throws to `.samples([])` did the same for a failed read, on the
    /// mistaken grounds that a throw is how a revocation arrives.
    private func readSamples(now: Date) async -> SleepReadOutcome {
        do {
            return .samples(
                try await sleepQuery.sleepSamples(
                    from: now.addingTimeInterval(-lookback), to: now))
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
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
    /// this screen having no `.refreshable` and no scene-phase hook — nothing re-runs the query for as long
    /// as the reader stays on it (see `samplesBeforeDeadline` for the navigate-away-and-back escape, which
    /// the screen never offers). "Checking your movement…" until the reader gives up and leaves is the
    /// vanished section of WG-318 in its last costume: a spinner is not an answer, and it is the one failure
    /// the user cannot tell from a slow read.
    ///
    /// The loser of the race is **abandoned, not awaited** — see `firstResult`, which owns that rationale for
    /// both bounded reads.
    ///
    /// Nothing came back, so `.timedOut` reports a *read* that failed. Not a permission or hardware claim:
    /// the query got far enough to be waiting on the sensor, so we have no evidence for either, and
    /// `.temporarilyUnavailable` — which `applyMovementSummary` maps this to once it has established there
    /// is nothing to preserve — is the one reason that asks the user to change nothing.
    ///
    /// `.timedOut` rather than that `.unavailable` directly: an `.unavailable` is applied unconditionally,
    /// so a timeout would erase a correct estimate that is still the best answer available.
    private func summaryBeforeDeadline(now: Date) async -> MovementSummary {
        await firstResult(
            of: { await self.movementSummary(now: now) }, orAfter: movementTimeout,
            yielding: .timedOut) ?? .cancelled
    }

    /// Race `work` against `timeout`, returning whichever answers first — `timedOut` if the deadline wins,
    /// and `nil` if the stream ends with no winner, which happens only when *this* task was cancelled.
    ///
    /// Shared by both bounded reads on this screen (WG-318's motion query, WG-319's sleep query). They are
    /// the same race against the same hazard — a one-shot framework completion handler with no delivery
    /// guarantee — and two hand-rolled copies of a subtlety this specific is how one of them silently
    /// regresses.
    ///
    /// **The loser is abandoned, not awaited, and that is the whole design.** A structured
    /// `withThrowingTaskGroup` cancels its remaining children and then *waits for them* on scope exit, so
    /// against a source that does not honour cancellation it is inert while looking correct.
    ///
    /// **What that argument does *not* say**, though an earlier version of this comment did: it is not a
    /// claim that the shipped adapters are such a source. Both `HealthKitSleepQueryAdapter` and
    /// `CoreMotionActivityHistoryAdapter` wrap their continuation in `withTaskCancellationHandler` and resume
    /// with `CancellationError` immediately, so the structured form would in fact work against them **today**.
    /// The hazard this bounds is a completion handler that never fires, which is orthogonal to whether the
    /// adapter honours cancellation, and the two were conflated.
    ///
    /// The design is kept anyway, on the weaker and true argument: the deadline's guarantee should not be
    /// conditional on a property of the dependency that no signature enforces and that a future adapter — or
    /// a `stop`-less framework call — can silently drop. `testAQueryThatNeverAnswersDoesNotLeaveAPermanentSpinner`
    /// and `testASleepQueryThatNeverAnswersDoesNotLeaveAPermanentSpinner` use doubles that ignore
    /// cancellation so that regression is caught here rather than becoming a spinner on a device.
    ///
    /// Abandoning leaks the in-flight read until the framework releases it. A one-shot hardware or HealthKit
    /// query cannot be un-started, so the choice is only *who waits* — and a leaked read the user cannot see
    /// is strictly better than a spinner they can. `work.cancel()` still reclaims it promptly for any source
    /// that honours cancellation, which both real adapters do.
    private func firstResult<Outcome: Sendable>(
        of work: @escaping @MainActor () async -> Outcome, orAfter timeout: Duration,
        yielding timedOut: Outcome
    ) async -> Outcome? {
        let (outcomes, publish) = AsyncStream<Outcome>.makeStream()
        let read = Task { publish.yield(await work()) }
        let deadline = Task {
            try await Task.sleep(for: timeout)
            publish.yield(timedOut)
        }
        defer {
            read.cancel()
            deadline.cancel()
        }
        for await first in outcomes { return first }
        return nil
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
