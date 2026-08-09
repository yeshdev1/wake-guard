import XCTest

@testable import WakeGuard

/// WG-081: the bounded, on-demand recent-movement query. Verifies the query window is bounded (and
/// clamped), that clock changes and stale samples are handled (a backward / forward jump can't
/// fabricate recent movement), that it fails closed on a non-finite clock or an unavailable source,
/// and that the recency ladder reports the tightest rung containing a step. No continuous sensing:
/// every call is a fixed set of one-shot historical queries.
final class RecentMovementQueryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func sample(at timestamp: Date, steps: Int) -> PedometerSample {
        PedometerSample(
            timestamp: timestamp, quality: .high, stepCount: steps, distanceMeters: nil,
            cadenceStepsPerSecond: nil, secondsSinceLastStep: nil)
    }

    private func query(
        _ samples: [PedometerSample], availability: MotionSourceAvailability = .available,
        config: RecentMovementQuery.Config = .default
    ) -> RecentMovementQuery {
        RecentMovementQuery(
            source: FakeHistoricalPedometerSource(
                availabilityState: availability, cannedSamples: samples), config: config)
    }

    // MARK: - Fail-closed edges

    func testNonFiniteClockYieldsEmptySnapshot() async {
        let snap = await query([sample(at: now, steps: 50)]).snapshot(
            now: Date(timeIntervalSince1970: .nan))
        XCTAssertEqual(snap, .empty)
        XCTAssertNil(snap.window)
        XCTAssertFalse(snap.movementDetected)
    }

    func testDegenerateLadderYieldsEmptySnapshot() async {
        let config = RecentMovementQuery.Config(recencyLadderSeconds: [-5, 0, .nan, .infinity])
        let snap = await query([sample(at: now.addingTimeInterval(-60), steps: 50)], config: config)
            .snapshot(now: now)
        XCTAssertEqual(snap, .empty)
    }

    func testUnavailableSourceFailsClosedToNoMovement() async {
        let snap = await query(
            [sample(at: now.addingTimeInterval(-60), steps: 40)], availability: .notAuthorized
        ).snapshot(now: now)
        XCTAssertFalse(
            snap.movementDetected, "an unavailable source never fabricates recent movement")
        XCTAssertFalse(snap.sourceAvailable, "the pedometer couldn't be observed")
        XCTAssertNotNil(snap.window, "a window was still constructed")
    }

    func testTransientUnavailabilityFailsClosed() async {
        let snap = await query(
            [sample(at: now.addingTimeInterval(-60), steps: 40)],
            availability: .temporarilyUnavailable
        ).snapshot(now: now)
        XCTAssertFalse(snap.movementDetected)
        XCTAssertFalse(snap.sourceAvailable)
    }

    // MARK: - Bounded window

    func testWidestWindowSpansTheLargestRungClampedToMaxSpan() async {
        let config = RecentMovementQuery.Config(
            recencyLadderSeconds: [300, 10 * PedometerQueryWindow.maxSpan])
        let snap = await query([], config: config).snapshot(now: now)
        XCTAssertEqual(snap.window?.end, now)
        XCTAssertEqual(
            snap.window.map { $0.end.timeIntervalSince($0.start) }, PedometerQueryWindow.maxSpan,
            "the overlong rung clamps to the maximum span")
    }

    func testNoStepsReportsNoMovementButStillQueriesAWindow() async {
        let snap = await query([]).snapshot(now: now)
        XCTAssertFalse(snap.movementDetected)
        XCTAssertEqual(snap.stepCount, 0)
        XCTAssertEqual(snap.secondsSinceLastMovement, .infinity)
        XCTAssertTrue(snap.sourceAvailable, "confirmed still — distinct from couldn't-observe")
        XCTAssertNotNil(snap.window)
    }

    // MARK: - Recency ladder

    func testMovementInTightestRungGivesTightRecency() async {
        let snap = await query([sample(at: now.addingTimeInterval(-60), steps: 40)]).snapshot(
            now: now)
        XCTAssertTrue(snap.movementDetected)
        XCTAssertEqual(snap.stepCount, 40)
        XCTAssertEqual(
            snap.secondsSinceLastMovement, 180, "the step falls inside the tightest 180 s rung")
    }

    func testMovementOnlyInWiderRungGivesWiderRecency() async {
        let snap = await query([sample(at: now.addingTimeInterval(-400), steps: 40)]).snapshot(
            now: now)
        XCTAssertEqual(snap.stepCount, 40)
        XCTAssertEqual(
            snap.secondsSinceLastMovement, 600, "a step 400 s ago is outside 180 s but within 600 s"
        )
    }

    // MARK: - Clock changes and stale samples

    func testForwardClockJumpMakesOldSamplesStale() async {
        // Recorded long ago (t=1000); the clock has since jumped ~23 days forward, past every rung.
        let snap = await query([sample(at: Date(timeIntervalSince1970: 1000), steps: 500)])
            .snapshot(
                now: now)
        XCTAssertFalse(
            snap.movementDetected, "a sample from before the window is stale, not recent movement")
        XCTAssertEqual(snap.secondsSinceLastMovement, .infinity)
    }

    func testBackwardClockJumpDropsFutureStampedSamples() async {
        // The clock jumped backward, so a real sample now carries a timestamp after `now`.
        let snap = await query([sample(at: now.addingTimeInterval(300), steps: 500)]).snapshot(
            now: now)
        XCTAssertFalse(snap.movementDetected, "a future-stamped sample can't be recent movement")
    }

    // MARK: - Saturation

    func testHugeStepCountsSaturateWithoutTrapping() async {
        let timestamp = now.addingTimeInterval(-60)
        let snap = await query([
            sample(at: timestamp, steps: .max), sample(at: timestamp, steps: .max),
        ])
        .snapshot(now: now)
        XCTAssertEqual(snap.stepCount, .max, "the window step total saturates rather than trapping")
        XCTAssertTrue(snap.movementDetected)
    }

    // MARK: - Real-adapter mechanism (per-window counts at a constant endDate)

    func testRecencyViaRealAdapterMechanismPerWindowCounts() async {
        let source = WindowAwareHistoricalFake(stepEventTimes: [now.addingTimeInterval(-400)])
        let snap = await RecentMovementQuery(source: source).snapshot(now: now)
        XCTAssertEqual(snap.stepCount, 20)
        XCTAssertEqual(
            snap.secondsSinceLastMovement, 600,
            "recency comes from per-window counts at a constant endDate, not from timestamps")
        XCTAssertTrue(snap.sourceAvailable)
    }

    func testMultipleBurstsReportTightestRungAndFullCount() async {
        let source = WindowAwareHistoricalFake(
            stepEventTimes: [now.addingTimeInterval(-90), now.addingTimeInterval(-500)])
        let snap = await RecentMovementQuery(source: source).snapshot(now: now)
        XCTAssertEqual(snap.stepCount, 40, "both bursts count toward the widest-window total")
        XCTAssertEqual(
            snap.secondsSinceLastMovement, 180, "the most recent burst sets the tightest rung")
    }

    /// KNOWN LIMITATION (WG-081): aggregate pedometer history exposes only a per-window count stamped
    /// at the window end, so recency is quantized to the ladder's rungs — a step 181 s ago reports
    /// the next rung up (600), never ~181. Pinned intentionally; it is an honest UPPER bound and,
    /// being advisory, can only ever loosen a pre-alarm prompt, never suppress an alarm (#8).
    func testRecencyIsRungQuantizedKnownLimitation() async {
        let source = WindowAwareHistoricalFake(stepEventTimes: [now.addingTimeInterval(-181)])
        let snap = await RecentMovementQuery(source: source).snapshot(now: now)
        XCTAssertEqual(
            snap.secondsSinceLastMovement, 600, "just outside the 180 s rung → 600, not ~181")
    }
}

/// A window-aware fake emulating the real CoreMotion adapter: one aggregate sample per query, stamped
/// at `window.end` (like `CMPedometerData.endDate`), counting only the step events inside
/// `[start, end]`. Unlike `FakeHistoricalPedometerSource`, recency here is carried by per-window
/// COUNTS at a constant timestamp — the real-device mechanism the production adapter produces.
private struct WindowAwareHistoricalFake: HistoricalPedometerSource {
    let stepEventTimes: [Date]
    var stepsPerEvent = 20

    func availability() async -> MotionSourceAvailability { .available }

    func samples(in window: PedometerQueryWindow) async throws -> [PedometerSample] {
        let count = stepEventTimes.filter { $0 >= window.start && $0 <= window.end }.count
        return [
            PedometerSample(
                timestamp: window.end, quality: .high, stepCount: count * stepsPerEvent,
                distanceMeters: nil, cadenceStepsPerSecond: nil, secondsSinceLastStep: nil)
        ]
    }
}
