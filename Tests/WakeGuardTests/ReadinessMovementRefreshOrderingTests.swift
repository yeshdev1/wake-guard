import XCTest

@testable import WakeGuard

/// WG-318: what the "Movement overnight" section shows **while** a refresh is in flight, and when two
/// refreshes overlap. Split from `ReadinessMovementUnavailabilityTests` for SwiftLint `file_length`.
///
/// These are the cases a double that returns immediately cannot express. Both defects here were found by
/// review on a green suite: the section was blanked for the duration of every query, and a superseded
/// refresh could overwrite a fresher result purely by finishing later.
@MainActor
final class ReadinessMovementRefreshOrderingTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }

    /// The same real night as `ReadinessMovementUnavailabilityTests.nightSamples()` — still from 18:53, a
    /// 10-minute disturbance inside the night at 01:53, then a sustained walk from 03:53 that closes it.
    private func nightSamples() -> [MotionActivitySample] {
        [
            MotionActivitySample(
                timestamp: base.addingTimeInterval(-36_000), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: base.addingTimeInterval(-10_800), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: base.addingTimeInterval(-10_200), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: base.addingTimeInterval(-3_600), quality: .high, kind: .walking),
        ]
    }

    /// The cold open — the window WG-318 is hit in most often, and the one it missed. `refresh` publishes
    /// `assessment` *before* awaiting the motion query, so the card appears immediately while the movement
    /// section has neither an estimate nor a reason: it renders nothing at all. That is precisely the
    /// silently-vanishing section WG-318 exists to remove, surviving inside its own fix.
    ///
    /// The section is empty on **every** first open, for as long as the CoreMotion query takes.
    func testTheSectionIsNeverEmptyWhileTheCardIsOnScreen() async {
        let motion = GatedMotionHistory()
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())

        let first = Task { await model.refresh(now: base) }
        await motion.waitForQueries(1)

        // The card renders as soon as `assessment` is non-nil, so this is not an invisible intermediate
        // state — it is what a user sees on launch.
        XCTAssertNotNil(model.assessment, "the card is already on screen")
        XCTAssertEqual(
            model.movement, .loading,
            "the section must say it is checking, not render nothing, while the query runs")
        // The original reproduction, kept in its own terms: before `.loading` existed, both of these were
        // `nil` here and the card's `if let / else if let` chain fell through to no view at all.
        XCTAssertNil(model.estimatedDisturbances, "no estimate has arrived yet")
        XCTAssertNil(
            model.movementUnavailability, "and nothing has gone wrong, so there is no reason")

        await motion.finish(0, with: nightSamples())
        await first.value
        XCTAssertEqual(
            model.movement,
            .available(SleepDisturbances(pickups: 1, movingDuration: 600), rest: 25_200),
            "and the result replaces the loading state once it arrives")
    }

    /// `.loading` must be the state only *before* a first result — never a state a finished refresh can
    /// leave behind, which would be a spinner that never resolves.
    func testAFinishedRefreshNeverLeavesTheSectionLoading() async {
        let motion = GatedMotionHistory()
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())

        let refresh = Task { await model.refresh(now: base) }
        await motion.waitForQueries(1)
        await motion.fail(0, with: MotionSourceError.unavailable(.notAuthorized))
        await refresh.value

        XCTAssertEqual(model.movement, .unavailable(.accessUnavailable))
        XCTAssertNotEqual(
            model.movement, .loading, "a failed query is a conclusion, not still-working")
    }

    /// The same invariant for the case the name covers but the failing-query test does not: a **cancelled
    /// first** refresh. `.cancelled` deliberately preserves prior state, but on a cold open there is no
    /// prior state — so preserving it left `.loading` as the resting state with no query in flight and none
    /// scheduled: a spinner that never resolves, which is the vanished section in another costume.
    func testACancelledFirstRefreshDoesNotLeaveAPermanentSpinner() async {
        let motion = GatedMotionHistory()
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())

        let refresh = Task { await model.refresh(now: base) }
        await motion.waitForQueries(1)
        await motion.fail(0, with: CancellationError())
        await refresh.value

        XCTAssertNotEqual(
            model.movement, .loading,
            "nothing is running, so 'Checking your movement…' would be a permanent falsehood")
        XCTAssertEqual(
            model.movement, .unavailable(.temporarilyUnavailable),
            "nothing was read, so the honest terminal state is that we couldn't read it")
    }

    /// The cold-open cancellation fallback must not fire while a **newer** refresh is still running. The
    /// adapter checks cancellation *before* the CoreMotion call, so a cancelled older refresh returns fast
    /// while the newer one is still awaiting hardware: without the generation clause the section flashes
    /// "we couldn't read your movement data" about a read that is at that moment in progress — a failure
    /// claim we do not have. `.loading` is the honest state there, because something genuinely is loading.
    func testACancelledOlderRefreshDoesNotReportFailureWhileANewerOneIsStillRunning() async {
        let motion = GatedMotionHistory()
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())

        let older = Task { await model.refresh(now: base) }
        await motion.waitForQueries(1)
        let newer = Task { await model.refresh(now: base) }
        await motion.waitForQueries(2)

        await motion.fail(0, with: CancellationError())
        await older.value

        XCTAssertEqual(
            model.movement, .loading,
            "a newer query is still in flight, so claiming the read failed states more than we know"
        )

        await motion.finish(1, with: nightSamples())
        await newer.value
        XCTAssertNotEqual(model.movement, .loading, "the newer result must still land")
        XCTAssertNotEqual(
            model.movement, .unavailable(.temporarilyUnavailable),
            "the newer refresh succeeded, so no failure reason may remain on screen")
    }

    /// A query whose answer **never arrives**. `CoreMotionActivityHistoryAdapter` awaits a one-shot
    /// completion handler with no deadline, so a handler that never fires leaves `movement` at `.loading`
    /// for as long as the reader stays on the screen — there is no `.refreshable` and no scene-phase hook, so
    /// nothing re-runs the query. (Navigating back and pushing the screen again rebuilds its `@State` model
    /// and does re-run `.task`, but the screen never offers that escape; an earlier version of this comment
    /// said "for the life of the process", which is false.) "Checking your movement…" until the reader gives
    /// up is not a state they can distinguish from a slow read, and it is WG-318's vanished section in its
    /// last costume: a spinner is not an answer.
    ///
    /// The double ignores cancellation on purpose (see `GatedMotionHistory`) — a deadline that cancels its
    /// racer and then waits for it is inert against a source that ignores cancellation. Not a claim that
    /// `CoreMotionActivityHistoryAdapter` is such a source (it is not; it resumes on cancellation), but the
    /// deadline must not *depend* on that. See `ReadinessViewModel.firstResult`.
    func testAQueryThatNeverAnswersDoesNotLeaveAPermanentSpinner() async {
        let motion = GatedMotionHistory()
        // The only test that injects a deadline. Both directions are deterministic rather than timing-
        // dependent: this source never answers, so the deadline always wins, and every other test leaves the
        // 15s default in place against a double that answers the moment the test says so.
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar(),
            movementTimeout: .milliseconds(50))

        let refresh = Task { await model.refresh(now: base) }
        await motion.waitForQueries(1)
        XCTAssertEqual(model.movement, .loading, "the query is genuinely in flight")

        // Returns only because the deadline fires; without one this never returns at all.
        await refresh.value

        XCTAssertNotEqual(
            model.movement, .loading,
            "nothing will ever answer this query, so 'Checking your movement…' is a permanent falsehood"
        )
        XCTAssertEqual(
            model.movement, .unavailable(.temporarilyUnavailable),
            "nothing was read, so the honest terminal state is that we couldn't read it")

        // Release the abandoned read so the double is not left holding an unresumed continuation.
        await motion.finish(0, with: [])
    }

    /// The deadline must not fire on a read that is merely **slow**. Every test above injects
    /// `.milliseconds(50)` so the timeout direction is deterministic, which leaves the **production**
    /// `movementTimeout` exercised by nothing: `.milliseconds(15)` in place of `.seconds(15)` — one word —
    /// would ship green while the section abandoned every real CoreMotion read and told every user their
    /// movement couldn't be checked. No mutation of the *mechanism* can reach it; the mechanism is correct and
    /// the constant is wrong.
    ///
    /// The sibling constant has had this cover since WG-319
    /// (`ReadinessCardLoadBoundTests.testTheDefaultDeadlineDoesNotAbandonAReadThatIsStillRunning`); this one
    /// did not, which is round seven's "which sibling branches does this rule also govern" missed one layer
    /// down. Asserted as a **property** — a read still in flight after 150ms has not been abandoned — so it
    /// survives `SMK-16` replacing the 15s guess with a measured value.
    func testTheDefaultDeadlineDoesNotAbandonAMovementReadThatIsStillRunning() async throws {
        let motion = GatedMotionHistory()
        // Deliberately no `movementTimeout:` — this test exists to exercise the shipped default.
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())

        let refresh = Task { await model.refresh(now: base) }
        await motion.waitForQueries(1)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(
            model.movement, .loading,
            """
            the query is still in flight, so the deadline must not have fired — a deadline shorter than a \
            real CoreMotion read makes "we couldn't read it" the permanent state for everyone
            """)

        await motion.finish(0, with: nightSamples())
        await refresh.value

        guard case .available = model.movement else {
            return XCTFail(
                "and the slow read still lands, rather than being discarded by a fired deadline")
        }
    }

    /// A deadline read **nothing**, which is the same epistemic state as a cancellation — and the ADR's
    /// assumption (b) already settled what to do with it: "replacing a good estimate with nothing would blank
    /// a correct section in order to say less than it already said."
    ///
    /// The deadline shipped without that treatment. It yielded `.unavailable(.temporarilyUnavailable)`, which
    /// `applyMovementSummary` applies unconditionally, so a correct 8-hour night on screen was replaced by
    /// "We couldn't read your movement data just now." — copy that deliberately carries no retry instruction,
    /// on a screen with no `.refreshable`. Two opposite policies for one condition, with the ADR documenting
    /// only one of them.
    ///
    /// Latent today (a single `.task` means no second refresh), which is exactly the status `movementGeneration`
    /// has — and that guard was hardened anyway, on the reasoning that it "becomes load-bearing the moment
    /// either is added". The cold-open direction stays covered by
    /// `testAQueryThatNeverAnswersDoesNotLeaveAPermanentSpinner`: with nothing to preserve, a timeout must
    /// still resolve the spinner.
    func testATimedOutRefreshDoesNotEraseAGoodEstimate() async {
        let motion = GatedMotionHistory()
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar(),
            movementTimeout: .milliseconds(50))

        let first = Task { await model.refresh(now: base) }
        await motion.waitForQueries(1)
        await motion.finish(0, with: nightSamples())
        await first.value
        let established = model.movement
        guard case .available = established else {
            return XCTFail("the first refresh must establish a real estimate to preserve")
        }

        // The second query never answers, so the deadline wins the race.
        let second = Task { await model.refresh(now: base) }
        await motion.waitForQueries(2)
        await second.value

        XCTAssertEqual(
            model.movement, established,
            """
            a timeout read nothing, so it must not replace a correct estimate with a failure the user \
            cannot retry from this screen
            """)

        // Release the abandoned read so the double is not left holding an unresumed continuation.
        await motion.finish(1, with: [])
    }

    /// Clearing the estimates up front meant a populated section went blank for the whole duration of every
    /// query, so the section disappeared and came back on each refresh.
    func testAnInFlightRefreshDoesNotBlankTheSectionItIsAboutToRepopulate() async {
        let motion = GatedMotionHistory()
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())

        let first = Task { await model.refresh(now: base) }
        await motion.waitForQueries(1)
        await motion.finish(0, with: nightSamples())
        await first.value
        let established = model.estimatedDisturbances
        XCTAssertNotNil(established)

        let second = Task { await model.refresh(now: base) }
        await motion.waitForQueries(2)

        XCTAssertEqual(
            model.estimatedDisturbances, established,
            "the previous estimate must stay on screen until the new one replaces it")

        await motion.finish(1, with: nightSamples())
        await second.value
    }

    /// Two overlapping refreshes: the newer one returns a good night, then the older one throws. Without a
    /// generation guard the older answer wins purely by finishing last, and the user is told access is
    /// unavailable while access is granted and a valid estimate had already arrived.
    func testAStaleRefreshDoesNotOverwriteANewerResult() async {
        let motion = GatedMotionHistory()
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())

        let older = Task { await model.refresh(now: base) }
        await motion.waitForQueries(1)
        let newer = Task { await model.refresh(now: base) }
        await motion.waitForQueries(2)

        await motion.finish(1, with: nightSamples())
        await newer.value
        XCTAssertNotNil(model.estimatedDisturbances, "the newer refresh found a night")

        await motion.fail(0, with: MotionSourceError.unavailable(.notAuthorized))
        await older.value

        XCTAssertNotNil(
            model.estimatedDisturbances,
            "a superseded refresh must not replace a fresher estimate by finishing later")
        XCTAssertNil(
            model.movementUnavailability,
            "and must not claim access is off while a valid estimate is on screen")
    }

    /// The newest refresh is cancelled and the older one succeeds. Under an `==` generation guard the older
    /// result is dropped for not being newest and the cancelled one writes nothing — so *neither* applies
    /// and the section vanishes with nothing said, which is the bug WG-318 exists to remove, recreated by
    /// its own fix. Cancellation is not a result, so it must not claim a generation.
    func testACancelledNewestRefreshDoesNotStarveAnOlderOneThatSucceeded() async {
        let motion = GatedMotionHistory()
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())

        let older = Task { await model.refresh(now: base) }
        await motion.waitForQueries(1)
        let newest = Task { await model.refresh(now: base) }
        await motion.waitForQueries(2)

        await motion.fail(1, with: CancellationError())
        await newest.value
        await motion.finish(0, with: nightSamples())
        await older.value

        XCTAssertNotNil(
            model.estimatedDisturbances,
            "a cancelled refresh is not an answer — it must not invalidate the one that arrived")
        XCTAssertNil(model.movementUnavailability)
    }
}

// MARK: - Doubles

private struct StubSleepSource: SleepSampleQuerying {
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] { [] }
}
