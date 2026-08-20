import Foundation
import XCTest

@testable import WakeGuard

/// WG-319: the readiness **card**'s load path, as distinct from the movement *section* inside it that
/// WG-318 spent ten rounds bounding.
///
/// `ReadinessScreenContent` renders the card only when `assessment != nil` and otherwise a
/// `ProgressView("Checking your sleep readiness…")` with no bound, while `assessment` is assigned only
/// *after* `await sleepQuery.sleepSamples(...)` — which has no deadline in the view model and none in
/// `HealthKitSleepQueryAdapter`, an `HKSampleQuery` completion handler awaited through a continuation. That
/// is the same shape `CoreMotionActivityHistoryAdapter` had before WG-318's eighth round, with a strictly
/// larger blast radius: the section spinning hid one section, this hides the whole card — including the
/// always-on movement section WG-318 exists to guarantee.
///
/// The screen has no `.refreshable` and no scene-phase hook, so nothing re-runs the query: the spinner is
/// terminal for as long as the reader stays on the screen. It is **not** terminal for the life of the
/// process, as this comment previously claimed — `AlarmListView` pushes the screen through a
/// `NavigationLink` and `ReadinessScreenContent` owns its model in `@State`, so popping back and re-entering
/// builds a fresh model and re-runs `.task`. That is a real escape and it is why the defect is a stuck
/// screen rather than a stuck app; it is not a mitigation, because the screen never offers it and a reader
/// watching a spinner has no reason to guess that leaving is the way to make it work.
@MainActor
final class ReadinessCardLoadBoundTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// One night's asleep interval, `dayOffset` days before `base` — enough for a readiness with factors,
    /// so "a good assessment on screen" is a real value and not a sentinel a presence check would flatter.
    private func night(dayOffset: Int, asleepHours: Double = 7) -> [SleepSample] {
        let start = base.addingTimeInterval(Double(dayOffset) * 86_400)
        return [
            SleepSample(
                category: .asleep,
                interval: DateInterval(
                    start: start, end: start.addingTimeInterval(asleepHours * 3_600)))
        ]
    }

    private func twoGoodNights() -> [SleepSample] { night(dayOffset: -1) + night(dayOffset: -2) }

    // MARK: - The reproduction: a read that never answers

    /// **The WG-319 reproduction.** A sleep query whose completion never arrives leaves `assessment` at
    /// `nil` forever, so the card never renders and the spinner is permanent.
    ///
    /// The defect is a **hang**, so the artefact is the test being killed by
    /// `-default-test-execution-time-allowance` rather than an assertion failing — the round-eight pattern,
    /// which is cleaner evidence than an assertion because there is no way to satisfy it accidentally.
    /// `GatedSleepSource` ignores cancellation on purpose: a deadline that cancels its racer and then waits
    /// for it is inert against exactly the hung source it exists to survive.
    func testASleepQueryThatNeverAnswersDoesNotLeaveAPermanentSpinner() async {
        let sleep = GatedSleepSource()
        // The deadline is injected only where it must fire, and both directions stay deterministic rather
        // than timing-dependent: this source never answers, so the deadline always wins, while every other
        // test leaves the 15s default against a double that answers the moment the test says so.
        let model = ReadinessViewModel(
            sleepQuery: sleep, calendar: makeCalendar(), sleepTimeout: .milliseconds(50))

        let refresh = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(1)
        XCTAssertEqual(
            model.readiness, .loading,
            "the query is genuinely in flight, so the spinner is honest here")

        // Returns only because the deadline fires; without one this never returns at all.
        await refresh.value

        XCTAssertNotEqual(
            model.readiness, .loading,
            """
            nothing will ever answer this query, so "Checking your sleep readiness…" is a permanent \
            falsehood and the whole card — including the always-on movement section — stays hidden
            """)

        // Release the abandoned read so the double is not left holding an unresumed continuation.
        await sleep.finish(0, with: [])
    }

    // MARK: - A timeout read nothing, so it is not a result

    /// A deadline that fires read **nothing**, which is the same epistemic state as a cancellation — and
    /// WG-318's round ten already settled what to do with it on the sibling path: `MovementSummary.timedOut`
    /// exists precisely because applying a timeout as a failure erased a correct estimate.
    ///
    /// The card must not learn the opposite lesson. A timeout replacing a real readiness with "not enough
    /// sleep data" would be two opposite policies for one condition on one screen.
    func testATimedOutReadDoesNotEraseAGoodAssessment() async throws {
        let sleep = GatedSleepSource()
        let model = ReadinessViewModel(
            sleepQuery: sleep, calendar: makeCalendar(), sleepTimeout: .milliseconds(50))

        let first = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(1)
        await sleep.finish(0, with: twoGoodNights())
        await first.value
        let established = try XCTUnwrap(model.assessment)
        XCTAssertFalse(established.factors.isEmpty, "the fixture must establish a real readiness")

        // The second read never answers, so the deadline wins the race.
        let second = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(2)
        await second.value

        XCTAssertEqual(
            model.assessment, established,
            "a timeout read nothing, so it must not replace a correct readiness with a worse one")

        await sleep.finish(1, with: [])
    }

    /// The deadline must not fire on a read that is merely **slow**. Every other test in this file injects
    /// `.milliseconds(50)` so the timeout direction is deterministic, which means the **production** value is
    /// exercised by nothing: `.milliseconds(15)` in place of `.seconds(15)` — one word — would ship green
    /// while the card abandoned every real HealthKit read and told every user with data that there isn't
    /// enough of it. That is the harm WG-319 names in its own scope note, inverted, and no mutation of the
    /// mechanism can reach it: the mechanism is correct and the constant is wrong.
    ///
    /// Asserted as a **property** rather than by comparing the constant to itself: a read still in flight
    /// after 150ms has not been abandoned. That fails on a milliseconds slip and holds for any sane seconds
    /// value, so it does not have to be rewritten when `SMK-17`'s device measurement replaces the 15s guess.
    /// (`SMK-17`, not `SMK-16`: this exercises the **sleep** deadline. SMK-16 measures the movement section,
    /// and the sibling test on that path cites it correctly.)
    func testTheDefaultDeadlineDoesNotAbandonAReadThatIsStillRunning() async throws {
        let sleep = GatedSleepSource()
        // Deliberately no `sleepTimeout:` — this test exists to exercise the shipped default.
        let model = ReadinessViewModel(sleepQuery: sleep, calendar: makeCalendar())

        let refresh = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(1)
        try await Task.sleep(for: .milliseconds(150))

        // `.loading`, not merely "no assessment": since the degrade resolves to `.unavailable` rather than to
        // an empty assessment, `assessment == nil` is now satisfied by a read that *was* abandoned as well as
        // by one still running, and a units slip would survive it.
        XCTAssertEqual(
            model.readiness, .loading,
            """
            the query is still in flight, so the deadline must not have fired — a deadline shorter than a \
            real HealthKit read turns "we couldn't read it" into the permanent state for everyone
            """)

        await sleep.finish(0, with: twoGoodNights())
        await refresh.value

        XCTAssertFalse(
            try XCTUnwrap(model.assessment).factors.isEmpty,
            "and the slow read still lands, rather than being discarded by a deadline that already fired"
        )
    }

    /// The same rule for the other "nothing was read" outcome. `try?` collapsed `CancellationError` into an
    /// empty sample set, so a refresh cancelled by the screen going away *erased* a correct readiness and
    /// replaced it with "not enough sleep data" — a claim about the user's data made from a read that never
    /// happened.
    ///
    /// Kept as its own test rather than folded into the timeout one because it arrives by **different code**:
    /// the timeout is `firstResult`'s deadline branch, this is `readSamples`' `catch`. An earlier version of
    /// this comment justified it instead by "a single test would go green on half a fix", which is false —
    /// the two outcomes share one `switch` arm, so no half-fix exists that satisfies one and not the other.
    /// See `SleepReadOutcome.timedOut` for the mutation evidence.
    func testACancelledReadDoesNotEraseAGoodAssessment() async throws {
        let sleep = GatedSleepSource()
        let model = ReadinessViewModel(sleepQuery: sleep, calendar: makeCalendar())

        let first = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(1)
        await sleep.finish(0, with: twoGoodNights())
        await first.value
        let established = try XCTUnwrap(model.assessment)

        let second = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(2)
        await sleep.fail(1, with: CancellationError())
        await second.value

        XCTAssertEqual(
            model.assessment, established,
            "cancellation is not a result — it must not replace a good readiness with nothing")
    }

    // MARK: - The two routes to `.cancelled` are different code

    /// **The `?? .cancelled` in `samplesBeforeDeadline`, which nothing reached.** Every other cancellation
    /// test here makes the *source* throw `CancellationError`, which is caught in `readSamples` — a different
    /// line. This one cancels the refresh **task**, so `firstResult`'s `for await` ends with no winner and
    /// returns `nil`.
    ///
    /// It is the real shape: the screen is dismissed while a query is in flight, and SwiftUI cancels the
    /// `.task`. The double never answers, so the only way this returns at all is through that path — if
    /// `AsyncStream` did not terminate on cancellation, this test hangs rather than fails, which is the
    /// cleaner artefact.
    func testACancelledRefreshTaskResolvesThroughTheStreamRatherThanHanging() async {
        let sleep = GatedSleepSource()
        let model = ReadinessViewModel(sleepQuery: sleep, calendar: makeCalendar())

        let refresh = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(1)
        XCTAssertEqual(
            model.readiness, .loading, "the query is in flight, so the spinner is honest")

        refresh.cancel()
        await refresh.value

        // `.unavailable`, not merely "not `.loading`": a weaker assertion here is satisfied by
        // `?? .samples([])`, which would resolve the spinner by telling a cancelled reader their HealthKit is
        // empty — round twelve's finding 1 arriving by this route instead.
        XCTAssertEqual(
            model.readiness, .unavailable(.temporarilyUnavailable),
            """
            the refresh was cancelled and nothing is running, so the card must report a read that did not \
            happen — not a spinner, and not a claim about data it never looked at
            """)

        // Release the abandoned read so the double is not left holding an unresumed continuation.
        await sleep.finish(0, with: [])
    }

    /// **The cold-open cancellation.** WG-318's round six found exactly this hole on the movement path: the
    /// test named for "a finished refresh never leaves it loading" exercised only a *failing* finish, and the
    /// neighbouring cancellation test always established a good estimate first — so `.loading` was never the
    /// prior state and a cancelled cold open left a permanent spinner.
    ///
    /// The card inherited the same gap. `testATimedOutColdOpenDoesNotTellTheUserTheyHaveTooLittleSleepData`
    /// covers the timeout arriving at `.loading`; `testACancelledReadDoesNotEraseAGoodAssessment` covers
    /// cancellation arriving at a *populated* card. Cancellation arriving at `.loading` — the same
    /// `guard case .loading` line, reached by the other outcome — was covered by neither.
    func testACancelledColdOpenDoesNotLeaveAPermanentSpinner() async {
        let sleep = GatedSleepSource()
        let model = ReadinessViewModel(sleepQuery: sleep, calendar: makeCalendar())

        let refresh = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(1)
        await sleep.fail(0, with: CancellationError())
        await refresh.value

        XCTAssertEqual(
            model.readiness, .unavailable(.temporarilyUnavailable),
            """
            nothing was read and there is nothing to preserve, so leaving `.loading` would be a spinner with \
            no query behind it — the defect WG-319 exists to remove, reached by the cancellation route
            """)
    }

    // MARK: - A read that errored also read nothing

    /// **Round twelve, finding 4 — re-aimed.** The review reported this as "a revoked grant and a timed-out
    /// read render identically". That cause is **false**: HealthKit does not reveal read denial, so a revoked
    /// grant returns an empty sample set rather than throwing (which is why `HealthAccessStatesTests` models
    /// denial as `MutableSleepSource([])`). Every throw that is not a cancellation is therefore a genuine
    /// **read error** — and a read that errored learned nothing about the user's sleep.
    ///
    /// So the same falsehood reaches the card by a second route, and the stale-claim guarantee that appeared
    /// to justify replacing on a throw is in fact carried entirely by the empty-samples path.
    func testAnErroredColdOpenDoesNotTellTheUserTheyHaveTooLittleSleepData() async throws {
        let sleep = GatedSleepSource()
        let model = ReadinessViewModel(sleepQuery: sleep, calendar: makeCalendar())

        let refresh = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(1)
        await sleep.fail(0, with: HealthReadFailure())
        await refresh.value

        XCTAssertEqual(
            model.readiness, .unavailable(.temporarilyUnavailable),
            "the query failed, so the card must report a failed read rather than a data shortage")
    }

    /// And the preserve rule follows from the same correction. A read error learned nothing about the user's
    /// sleep, so it must not replace a correct readiness — exactly as a timeout must not, and for exactly the
    /// reason WG-318's round ten settled on the movement path.
    ///
    /// This **inverts** `testAConcludedFailureDoesReplaceAGoodAssessment`, which was written on the review's
    /// stated premise that a throw is how a revoked grant arrives. It isn't: a revoked grant returns `[]` and
    /// so travels the `.samples` path, which still replaces unconditionally. The "no stale readiness claim
    /// remains" guarantee is carried there, not here.
    func testAnErroredReadDoesNotEraseAGoodAssessment() async throws {
        let sleep = GatedSleepSource()
        let model = ReadinessViewModel(sleepQuery: sleep, calendar: makeCalendar())

        let first = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(1)
        await sleep.finish(0, with: twoGoodNights())
        await first.value
        let established = try XCTUnwrap(model.assessment)

        let second = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(2)
        await sleep.fail(1, with: HealthReadFailure())
        await second.value

        XCTAssertEqual(
            model.assessment, established,
            "a failed read is not a report that the user's data is gone — only an empty result is")
    }

    // MARK: - A concluded failure *is* a result

    /// The contrast that keeps the preserve rule from swallowing the case it must not cover: a query that
    /// **answered** is a result, so a good assessment on screen must be replaced by it. Without this, "a
    /// timeout preserves" generalizes silently into "any unwelcome outcome preserves", and a revoked grant
    /// would leave a stale readiness claim on screen — which `ReadinessViewModel`'s own docstring forbids.
    ///
    /// The revocation is expressed as an **empty sample set**, which is how one actually arrives: HealthKit
    /// does not reveal read denial, so an unauthorized read returns no samples rather than throwing. This
    /// test previously threw `HealthReadFailure` on the review's stated premise that a revocation is a throw;
    /// it therefore exercised the *read-error* path while asserting the *revocation* guarantee, and passing
    /// meant only that both were being collapsed into the same wrong answer. The read-error half now lives in
    /// `testAnErroredReadDoesNotEraseAGoodAssessment`, which asserts the opposite outcome for the opposite
    /// reason.
    func testARevokedGrantDoesReplaceAGoodAssessment() async throws {
        let sleep = GatedSleepSource()
        let model = ReadinessViewModel(sleepQuery: sleep, calendar: makeCalendar())

        let first = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(1)
        await sleep.finish(0, with: twoGoodNights())
        await first.value
        XCTAssertFalse(try XCTUnwrap(model.assessment).factors.isEmpty)

        let second = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(2)
        await sleep.finish(1, with: [])  // access revoked → HealthKit reports no samples
        await second.value

        XCTAssertTrue(
            try XCTUnwrap(model.assessment).factors.isEmpty,
            """
            an answered query is a conclusion, not a missing answer — leaving the previous readiness would \
            be exactly the stale claim the view model documents it never keeps
            """)
    }
}
