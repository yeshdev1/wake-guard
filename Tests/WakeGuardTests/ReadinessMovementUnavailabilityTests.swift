import XCTest

@testable import WakeGuard

/// WG-318 (M5/F7): when the "Movement overnight" estimate is unavailable the whole section vanishes —
/// header, both estimates and the "Estimated from movement" caveat together — and the three very different
/// reasons for that are indistinguishable to the user *and* to this test suite. Silence is the one thing a
/// safety-sensitive app may not do: the project rule is that the user is told what happened.
///
/// These tests pin the **reason**, not the copy. They are the reproduction: before WG-318 the view model
/// exposed only `estimatedDisturbances == nil` for all three causes.
@MainActor
final class ReadinessMovementUnavailabilityTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }

    /// A real night inside the candidate span. `base` is 2025-10-09 04:53:20 EDT, so the span opens at the
    /// previous local 18:00 (`base - 39_200`) and every sample sits inside it: still from 18:53, a 10-minute
    /// disturbance at 01:53 that is *inside* the night rather than the end of it, still again, then a
    /// sustained walk from 03:53 that closes the night.
    ///
    /// The shape matters. An earlier version was two samples — still, then walking at the night's end — and
    /// it was **fixture flattery**: the closing sample landed exactly on `night.end`, so re-clipping it
    /// inside the night window produced `end == start` and dropped it, and the "real night" reported
    /// `pickups: 0, movingDuration: 0` — bit-identical to `SleepDisturbances.none`, the "nothing happened"
    /// sentinel. Nothing asserted the value, so a `nightSpan` replaced by `samples.isEmpty ? nil : span`
    /// would have passed. `testAResolvedNightReportsTheNightsActualShape` now pins the numbers.
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

    // MARK: - The three causes must be distinguishable

    func testNoMotionSourceWiredReportsThatTheDeviceCannotTrackMovement() async {
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: nil, calendar: makeCalendar())
        await model.refresh(now: base)

        XCTAssertNil(model.estimatedDisturbances, "no motion source → no estimate")
        XCTAssertEqual(
            model.movementUnavailability, .sourceUnavailable,
            "a device that cannot report motion history is not the same as one that was denied access"
        )
    }

    func testADeniedOrFailedMotionQueryReportsThatAccessIsUnavailable() async {
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(),
            motionHistory: SwitchableMotionHistory(
                error: MotionSourceError.unavailable(.notAuthorized)),
            calendar: makeCalendar())
        await model.refresh(now: base)

        XCTAssertNil(model.estimatedDisturbances, "a failed query → no estimate")
        XCTAssertEqual(
            model.movementUnavailability, .accessUnavailable,
            "denied access is actionable by the user and must not read as 'not enough data'")
    }

    /// A device with no activity hardware throws from the adapter's availability guard, so it landed in the
    /// same catch as a denied grant and was told to turn on a toggle that doesn't apply to it — the
    /// `.sourceUnavailable` copy was written for this user and was unreachable in production.
    func testHardwareThatCannotReportActivityIsNotReportedAsASettingsToggle() async {
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(),
            motionHistory: SwitchableMotionHistory(
                error: MotionSourceError.unavailable(.notPresent)),
            calendar: makeCalendar())
        await model.refresh(now: base)

        XCTAssertEqual(
            model.movementUnavailability, .sourceUnavailable,
            "a device that cannot report activity has no Settings toggle to fix")
    }

    /// The adapter throws `.temporarilyUnavailable` *after* confirming access is granted. Reporting that as
    /// a permission problem sends a user with a working grant to fix something that isn't broken.
    func testATransientQueryFailureIsNotReportedAsAPermissionProblem() async {
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(),
            motionHistory: SwitchableMotionHistory(
                error: MotionSourceError.unavailable(.temporarilyUnavailable)),
            calendar: makeCalendar())
        await model.refresh(now: base)

        XCTAssertEqual(
            model.movementUnavailability, .temporarilyUnavailable,
            "the grant is fine — the read failed, and the only useful advice is to try again")
    }

    /// Parental controls / MDM. "You can turn it on in Settings" is false here, and telling a user to do
    /// something they cannot do is worse than saying nothing.
    func testRestrictedAccessIsNotReportedAsFixableInSettings() async {
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(),
            motionHistory: SwitchableMotionHistory(
                error: MotionSourceError.unavailable(.restricted)),
            calendar: makeCalendar())
        await model.refresh(now: base)

        XCTAssertEqual(
            model.movementUnavailability, .accessRestricted,
            "a restricted grant is not one the user can flip")
    }

    /// A throw carrying no availability claim must not be read as one.
    func testAnUnrecognisedFailureIsNotReportedAsAPermissionProblem() async {
        struct Opaque: Error {}
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: SwitchableMotionHistory(error: Opaque()),
            calendar: makeCalendar())
        await model.refresh(now: base)

        XCTAssertEqual(model.movementUnavailability, .temporarilyUnavailable)
    }

    func testDataWithNoResolvableNightReportsNotEnoughMovementData() async {
        // Motion access granted and samples returned, but nothing that resolves a night: a single short
        // quiet lull well under `minimumNightDuration`.
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(),
            motionHistory: SwitchableMotionHistory([
                MotionActivitySample(
                    timestamp: base.addingTimeInterval(-1_800), quality: .high, kind: .stationary),
                MotionActivitySample(
                    timestamp: base.addingTimeInterval(-600), quality: .high, kind: .walking),
            ]),
            calendar: makeCalendar())
        await model.refresh(now: base)

        XCTAssertNil(model.estimatedDisturbances, "no night in the data → no estimate")
        XCTAssertEqual(
            model.movementUnavailability, .noNightFound,
            "the query succeeded; there is simply not enough movement data to call it a night")
    }

    func testAResolvedNightReportsNoUnavailabilityReason() async {
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: SwitchableMotionHistory(nightSamples()),
            calendar: makeCalendar())
        await model.refresh(now: base)

        XCTAssertNotNil(model.estimatedDisturbances, "the fixture is a real night")
        XCTAssertNil(
            model.movementUnavailability,
            "an available estimate must not also carry an unavailability reason")
    }

    /// Asserting only that the estimate is non-`nil` lets a `nightSpan` of
    /// `samples.isEmpty ? nil : span` pass, and lets the "real night" fixture report the same
    /// `pickups: 0, movingDuration: 0` as a night where nothing happened. Pin the shape, not the presence.
    func testAResolvedNightReportsTheNightsActualShape() async {
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: SwitchableMotionHistory(nightSamples()),
            calendar: makeCalendar())
        await model.refresh(now: base)

        XCTAssertEqual(
            model.estimatedDisturbances, SleepDisturbances(pickups: 1, movingDuration: 600),
            "one 10-minute disturbance inside the night — not zero, and not the closing walk as well"
        )
        XCTAssertEqual(
            model.estimatedRest, 25_200,
            "the longest quiet stretch is 18:53 to the 01:53 disturbance, not the whole night")
    }

    // MARK: - M4: the anchor is asserted at the view-model seam, not only in the estimator

    /// WG-313's anchor tests exercise a re-implementation of `applyMovementSummary` in a helper, and the
    /// only view-model double ignored the requested window — so a wrong anchor would have passed. This
    /// asserts the window `ReadinessViewModel` actually asks for: `[previous local 18:00, now]`.
    func testTheViewModelQueriesTheNightAnchoredWindowNotARollingOne() async throws {
        let motion = SwitchableMotionHistory(nightSamples())
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())
        await model.refresh(now: base)

        let windows = await motion.requestedWindows
        XCTAssertEqual(windows.count, 1, "one motion query per refresh")
        // `try?` here would defeat XCTUnwrap: an empty array would leave `window` nil and every
        // assertion below would silently pass against nil.
        let window = try XCTUnwrap(windows.first)
        // base is 2025-10-09 04:53:20 EDT; the previous local 18:00 is 10h53m20s earlier.
        XCTAssertEqual(
            window.start, base.addingTimeInterval(-39_200),
            "the window opens at the previous local 18:00, not at `now - 10h` (WG-310's rolling window)"
        )
        XCTAssertEqual(window.end, base, "the window closes at the read time")
    }

    // MARK: - Cancellation is not a failure the user should be told about

    /// M7: `try?` conflated `CancellationError` with a denied grant. A refresh cancelled by the view
    /// disappearing must not leave "we couldn't read your movement data" on screen — nothing went wrong.
    func testACancelledRefreshIsNotReportedAsDeniedAccess() async {
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(),
            motionHistory: SwitchableMotionHistory(error: CancellationError()),
            calendar: makeCalendar())
        await model.refresh(now: base)

        XCTAssertNil(model.estimatedDisturbances)
        XCTAssertNotEqual(
            model.movementUnavailability, .accessUnavailable,
            "a cancelled query is not a permission problem and must not be reported as one")
    }

    /// A cancelled refresh must not *blank* a section that already has a good estimate in it. The estimates
    /// were cleared before the query ran, so cancellation didn't merely fail to populate them — it wiped a
    /// correct answer and, since cancellation reports no reason, left nothing at all in its place.
    func testACancelledRefreshLeavesTheEstimateAlreadyOnScreen() async {
        let motion = SwitchableMotionHistory(nightSamples())
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())

        await model.refresh(now: base)
        let established = model.estimatedDisturbances
        XCTAssertNotNil(established, "the fixture is a real night")

        await motion.fail(with: CancellationError())
        await model.refresh(now: base)

        XCTAssertEqual(
            model.estimatedDisturbances, established,
            "cancellation is not a result — it must not replace a good estimate with nothing")
        XCTAssertNil(model.movementUnavailability, "and it is not a reason to show the user either")
    }

    // MARK: - The reason never outlives the condition that caused it

    func testTheReasonIsClearedWhenTheEstimateBecomesAvailableAgain() async {
        let motion = SwitchableMotionHistory()
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())

        await model.refresh(now: base)
        XCTAssertEqual(model.movementUnavailability, .noNightFound, "empty history → no night")

        await motion.set(samples: nightSamples())
        await model.refresh(now: base)
        XCTAssertNil(
            model.movementUnavailability,
            "a stale unavailability reason is as misleading as a stale estimate")
    }

    func testTheReasonReplacesAStaleEstimateWhenAccessIsRevoked() async {
        let motion = SwitchableMotionHistory(nightSamples())
        let model = ReadinessViewModel(
            sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())

        await model.refresh(now: base)
        XCTAssertNotNil(model.estimatedDisturbances)

        await motion.fail(with: MotionSourceError.unavailable(.notAuthorized))
        await model.refresh(now: base)
        XCTAssertNil(model.estimatedDisturbances, "a revoked grant must not leave a stale estimate")
        XCTAssertEqual(model.movementUnavailability, .accessUnavailable)
    }

    // MARK: - An estimate and a reason are never both absent, and never both present

    /// The invariant the doc comment used to only assert. Every non-cancelled path must land on exactly one
    /// of "here is an estimate" and "here is why there isn't one" — the failure mode being pinned is
    /// *neither*, which renders as the section vanishing with nothing said.
    func testEveryNonCancelledRefreshLeavesExactlyOneOfEstimateOrReason() async {
        func failing(_ availability: MotionSourceAvailability) -> SwitchableMotionHistory {
            SwitchableMotionHistory(error: MotionSourceError.unavailable(availability))
        }
        let cases: [(name: String, motion: SwitchableMotionHistory?)] = [
            ("no source wired", nil),
            ("empty history", SwitchableMotionHistory()),
            ("a real night", SwitchableMotionHistory(nightSamples())),
            ("denied", failing(.notAuthorized)),
            ("restricted", failing(.restricted)),
            ("no hardware", failing(.notPresent)),
            ("transient", failing(.temporarilyUnavailable)),
        ]
        for (name, motion) in cases {
            let model = ReadinessViewModel(
                sleepQuery: StubSleepSource(), motionHistory: motion, calendar: makeCalendar())
            await model.refresh(now: base)

            XCTAssertEqual(
                model.estimatedDisturbances == nil, model.movementUnavailability != nil,
                "\(name): exactly one of an estimate and a reason must be present")
            XCTAssertEqual(
                model.estimatedRest == nil, model.estimatedDisturbances == nil,
                "\(name): the two estimates come from one query and one night — never one without the other"
            )
        }
    }
}

// MARK: - Doubles

private struct StubSleepSource: SleepSampleQuerying {
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] { [] }
}

/// Unlike `HealthAccessStatesTests.FixedMotionHistory`, this double **honours the requested window** and
/// records it (M4). A stub that returns its whole fixture regardless of the window cannot detect a wrong
/// anchor — every anchor looks correct — which is why the view-model seam was effectively untested.
///
/// An `actor`, not an `@unchecked Sendable` class: the port is `Sendable` and `activitySamples` is
/// `nonisolated async`, so it runs off the main actor while the tests mutate the fixture from it.
private actor SwitchableMotionHistory: MotionActivityHistorySource {
    private var samples: [MotionActivitySample]
    private var error: (any Error)?
    private(set) var requestedWindows: [DateInterval] = []

    init(_ samples: [MotionActivitySample] = [], error: (any Error)? = nil) {
        self.samples = samples
        self.error = error
    }

    func set(samples: [MotionActivitySample]) {
        self.samples = samples
        error = nil
    }

    func fail(with error: any Error) { self.error = error }

    func activitySamples(in window: DateInterval) async throws -> [MotionActivitySample] {
        requestedWindows.append(window)
        if let error { throw error }
        return samples.filter { window.contains($0.timestamp) }
    }
}
