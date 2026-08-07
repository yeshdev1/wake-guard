import XCTest

@testable import WakeGuard

/// WG-067: the movement episode builder. Trace-tests that multiple streams merge by timestamp, that
/// pauses split episodes, that stale / future / out-of-order / non-finite observations are dropped,
/// that a cumulative-counter reset is handled without going negative, and — the canonical pair —
/// that continuous walking forms one sustained episode while intermittent bed movement does not.
final class MovementEpisodeTests: XCTestCase {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func obs(
        _ offset: TimeInterval, moving: Bool = true, steps: Int? = nil,
        source: MovementSource = .pedometer
    ) -> MovementObservation {
        MovementObservation(
            timestamp: Self.base.addingTimeInterval(offset), isMoving: moving,
            cumulativeSteps: steps,
            source: source)
    }

    private func now(_ offset: TimeInterval) -> Date { Self.base.addingTimeInterval(offset) }

    // MARK: - Bed movement vs walking (the canonical traces)

    func testWalkingFormsOneContinuousEpisode() {
        // A step every second for 12 s — sustained, no gaps.
        let stream = (0...12).map { obs(Double($0), steps: $0 * 5) }
        let episodes = MovementEpisodeBuilder.build(from: stream, now: now(13))
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.duration, 12)
        XCTAssertEqual(episodes.first?.observationCount, 13)
        XCTAssertEqual(episodes.first?.stepCount, 60)
    }

    func testBedMovementDoesNotFormSustainedEpisode() {
        // Intermittent tosses with long gaps — never a continuous stretch.
        let stream = [obs(0), obs(1), obs(20), obs(21), obs(40)]
        let episodes = MovementEpisodeBuilder.build(from: stream, now: now(41))
        XCTAssertEqual(episodes.count, 2, "each toss is a short episode; the lone one is dropped")
        XCTAssertTrue(
            episodes.allSatisfy { $0.duration <= 1 }, "bed movement forms no sustained episode")
    }

    // MARK: - Merge by timestamp

    func testMergesTwoStreamsByTimestamp() {
        let pedometer = [0, 2, 4, 6, 8, 10].enumerated().map {
            obs(Double($0.element), steps: $0.offset * 10, source: .pedometer)
        }
        let activity = [1, 3, 5, 7, 9].map { obs(Double($0), source: .activity) }
        let episodes = MovementEpisodeBuilder.build(merging: [pedometer, activity], now: now(11))
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.observationCount, 11, "both streams interleaved into one")
        XCTAssertEqual(episodes.first?.stepCount, 50, "steps come only from the pedometer stream")
        XCTAssertEqual(episodes.first?.start, Self.base)
        XCTAssertEqual(episodes.first?.end, now(10))
    }

    // MARK: - Pauses / stale / future / non-finite

    func testPauseSplitsEpisodes() {
        let stream = [obs(0), obs(1), obs(2), obs(10), obs(11), obs(12)]
        let episodes = MovementEpisodeBuilder.build(from: stream, now: now(13))
        XCTAssertEqual(episodes.count, 2)
        XCTAssertEqual(episodes.map(\.observationCount), [3, 3])
    }

    func testStaleObservationsDropped() {
        // The first observation is ~100 s before now — stale for a real-time judgment.
        let stream = [obs(0, steps: 5), obs(95, steps: 10), obs(96, steps: 12), obs(97, steps: 14)]
        let episodes = MovementEpisodeBuilder.build(from: stream, now: now(100))
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.observationCount, 3)
        XCTAssertEqual(episodes.first?.start, now(95))
    }

    func testFutureObservationsDropped() {
        let stream = [obs(0), obs(1), obs(2), obs(1000)]
        let episodes = MovementEpisodeBuilder.build(from: stream, now: now(3))
        XCTAssertEqual(episodes.first?.observationCount, 3, "a far-future observation is dropped")
    }

    func testNonFiniteTimestampDropped() {
        let corrupt = MovementObservation(
            timestamp: Date(timeIntervalSince1970: .nan), isMoving: true, source: .pedometer)
        let episodes = MovementEpisodeBuilder.build(from: [obs(0), obs(1), corrupt], now: now(2))
        XCTAssertEqual(episodes.first?.observationCount, 2)
    }

    func testStillObservationsFormNoEpisode() {
        let stream = (0...5).map { obs(Double($0), moving: false, source: .activity) }
        XCTAssertTrue(MovementEpisodeBuilder.build(from: stream, now: now(6)).isEmpty)
    }

    func testNonFiniteNowFailsClosed() {
        // A NaN clock makes the stale/future bounds NaN, which Date compares blind — the builder
        // must fail closed and emit nothing rather than pass every stale/future observation (B1).
        let stream = (0...12).map { obs(Double($0), steps: $0 * 5) }
        let episodes = MovementEpisodeBuilder.build(
            from: stream, now: Date(timeIntervalSince1970: .nan))
        XCTAssertTrue(
            episodes.isEmpty, "a non-finite clock disarms the freshness gate — fail closed")
    }

    // MARK: - Reset handling

    func testCumulativeResetFreezesAccountingAtPreResetRun() {
        // Cumulative steps climb (100->110), then the counter resets mid-episode. Accounting freezes
        // at the pre-reset run (10), never re-adding a fresh climb across the reset.
        let stream = [
            obs(0, steps: 100), obs(1, steps: 105), obs(2, steps: 110), obs(3, steps: 3),
            obs(4, steps: 8),
        ]
        let episodes = MovementEpisodeBuilder.build(from: stream, now: now(5))
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.stepCount, 10, "freeze at the pre-reset run; never negative")
    }

    func testInterleavedResetsCannotInflateSteps() {
        // A reset spammed between climbs must not re-add each climb (review S1: [100,5,105,5,110]
        // would otherwise report 205 phantom steps).
        let stream = [
            obs(0, steps: 100), obs(1, steps: 5), obs(2, steps: 105), obs(3, steps: 5),
            obs(4, steps: 110),
        ]
        let episodes = MovementEpisodeBuilder.build(from: stream, now: now(5))
        XCTAssertEqual(
            episodes.first?.stepCount, 0, "interleaved resets freeze accounting — no inflation")
    }

    // MARK: - Source mappers

    func testPedometerMapsToMovingObservationWithSteps() {
        let sample = PedometerSample(timestamp: Self.base, quality: .high, stepCount: 42)
        let observation = MovementObservation.from(pedometer: sample)
        XCTAssertTrue(observation.isMoving)
        XCTAssertEqual(observation.cumulativeSteps, 42)
        XCTAssertEqual(observation.source, .pedometer)
    }

    func testActivityMapsToMovingOnlyWhenOnFoot() {
        func sample(_ kind: MotionActivityKind) -> MotionActivitySample {
            MotionActivitySample(timestamp: Self.base, quality: .high, kind: kind)
        }
        XCTAssertTrue(MovementObservation.from(activity: sample(.walking)).isMoving)
        XCTAssertTrue(MovementObservation.from(activity: sample(.running)).isMoving)
        XCTAssertFalse(MovementObservation.from(activity: sample(.stationary)).isMoving)
        XCTAssertFalse(MovementObservation.from(activity: sample(.unknown)).isMoving)
        XCTAssertFalse(MovementObservation.from(activity: sample(.automotive)).isMoving)
    }

    // MARK: - Edges

    func testEmptyProducesNoEpisodes() {
        XCTAssertTrue(MovementEpisodeBuilder.build(from: [], now: Self.base).isEmpty)
    }

    func testSingleObservationIsNoEpisode() {
        XCTAssertTrue(MovementEpisodeBuilder.build(from: [obs(0)], now: now(1)).isEmpty)
    }
}
