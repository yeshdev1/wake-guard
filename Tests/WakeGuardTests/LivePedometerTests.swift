import XCTest

@testable import WakeGuard

/// WG-063: the live pedometer adapter's normalization + streaming contract. The pure
/// `LivePedometerNormalizer` is trace-tested for duplicate / out-of-order / invalid handling; the
/// `CoreMotionLivePedometerAdapter` is driven through a `FakeLivePedometerUpdates` seam to verify it
/// emits only ordered, valid samples from a recorded trace, is cancellation-safe (stops updates on
/// termination), and fails closed on unavailability / stream error. The CMPedometer mapping itself
/// is device-only (real-device checklist / UAT CP-C).
final class LivePedometerTests: XCTestCase {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func reading(offset: TimeInterval, steps: Int) -> PedometerReading {
        PedometerReading(timestamp: Self.base.addingTimeInterval(offset), stepCount: steps)
    }

    private func makeAdapter(
        _ updates: LivePedometerUpdates, availability: MotionSourceAvailability = .available
    ) -> CoreMotionLivePedometerAdapter {
        CoreMotionLivePedometerAdapter(
            updates: updates, availabilityProvider: { availability },
            now: { Self.base.addingTimeInterval(3600) })
    }

    /// Poll a synchronous condition, yielding between checks; fails the test if it never holds.
    private func waitUntil(_ message: String, _ condition: @Sendable () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("timed out waiting: \(message)")
    }

    // MARK: - Pure normalizer (recorded traces)

    private static let now = base.addingTimeInterval(3600)

    func testNormalizerDropsDuplicateAndOutOfOrder() {
        var normalizer = LivePedometerNormalizer()
        XCTAssertNotNil(normalizer.accept(reading(offset: 0, steps: 1), now: Self.now))
        XCTAssertNil(
            normalizer.accept(reading(offset: 0, steps: 2), now: Self.now), "duplicate timestamp")
        XCTAssertNil(
            normalizer.accept(reading(offset: -1, steps: 5), now: Self.now), "out-of-order")
        // The watermark advanced only on the one emitted sample, so a later valid reading emits.
        XCTAssertNotNil(normalizer.accept(reading(offset: 1, steps: 7), now: Self.now))
    }

    func testNormalizerDropsInvalidReading() {
        var normalizer = LivePedometerNormalizer()
        // Fresh normalizer (no prior count) so these reach validation, not the dedup/regression guards.
        XCTAssertNil(
            normalizer.accept(reading(offset: 0, steps: -3), now: Self.now), "negative steps")
        XCTAssertNil(
            normalizer.accept(
                PedometerReading(timestamp: Date(timeIntervalSince1970: .nan), stepCount: 1),
                now: Self.now), "non-finite timestamp")
        // Neither invalid reading advanced state, so a valid one still emits.
        XCTAssertNotNil(normalizer.accept(reading(offset: 0, steps: 4), now: Self.now))
    }

    func testNormalizerRejectsFutureTimestampAndKeepsWatermark() {
        var normalizer = LivePedometerNormalizer()
        XCTAssertNotNil(normalizer.accept(reading(offset: 0, steps: 2), now: Self.now))
        // A finite far-future stamp is dropped and must NOT poison the watermark (review B1).
        XCTAssertNil(
            normalizer.accept(
                PedometerReading(timestamp: Self.now.addingTimeInterval(86_400), stepCount: 3),
                now: Self.now), "implausibly future timestamp")
        // A subsequent real-time reading still emits — the watermark did not jump to the future.
        XCTAssertNotNil(normalizer.accept(reading(offset: 1, steps: 5), now: Self.now))
    }

    func testNormalizerDropsCumulativeStepRegression() {
        var normalizer = LivePedometerNormalizer()
        XCTAssertNotNil(normalizer.accept(reading(offset: 0, steps: 800), now: Self.now))
        // Advancing clock but the cumulative counter went backwards (reset/glitch) -> dropped (S1).
        XCTAssertNil(
            normalizer.accept(reading(offset: 1, steps: 5), now: Self.now), "cumulative regression")
        // Equal count on a fresh timestamp (stationary but live) is legitimate -> emitted.
        XCTAssertNotNil(normalizer.accept(reading(offset: 2, steps: 800), now: Self.now))
    }

    // MARK: - Adapter streaming (recorded trace through the seam)

    func testEmitsOnlyOrderedValidatedSamplesFromRecordedTrace() async throws {
        let fake = FakeLivePedometerUpdates()
        let adapter = makeAdapter(fake)
        let collector = Collector()
        let task = Task {
            for try await sample in adapter.samples() { collector.append(sample) }
        }
        await waitUntil("updates started") { fake.started }

        fake.emit(reading(offset: 0, steps: 3))
        fake.emit(reading(offset: 0, steps: 3))  // duplicate timestamp -> dropped
        fake.emit(reading(offset: -5, steps: 2))  // out-of-order -> dropped
        fake.emit(reading(offset: 1, steps: 6))
        fake.emit(reading(offset: 2, steps: -1))  // invalid -> dropped
        fake.emit(reading(offset: 3, steps: 9))

        await waitUntil("three samples collected") { collector.count == 3 }
        task.cancel()
        _ = await task.result

        XCTAssertEqual(collector.samples.map(\.stepCount), [3, 6, 9])
        XCTAssertGreaterThanOrEqual(fake.stopped, 1, "cancellation stops updates")
    }

    func testCancellationStopsUpdates() async {
        let fake = FakeLivePedometerUpdates()
        let adapter = makeAdapter(fake)
        let task = Task { for try await _ in adapter.samples() {} }
        await waitUntil("updates started") { fake.started }
        task.cancel()
        _ = await task.result
        await waitUntil("updates stopped on cancellation") { fake.stopped >= 1 }
    }

    func testUnavailableStreamThrowsWithoutStarting() async {
        let fake = FakeLivePedometerUpdates()
        let adapter = makeAdapter(fake, availability: .notAuthorized)
        let caught = await firstError(from: adapter.samples())
        XCTAssertEqual(caught as? MotionSourceError, .unavailable(.notAuthorized))
        XCTAssertFalse(fake.started, "an unavailable source must not start CoreMotion updates")
        XCTAssertEqual(fake.stopped, 0)
    }

    func testStreamErrorTerminatesAndStops() async {
        let fake = FakeLivePedometerUpdates()
        let adapter = makeAdapter(fake)
        let task = Task { () -> Error? in
            do {
                for try await _ in adapter.samples() {}
                return nil
            } catch {
                return error
            }
        }
        await waitUntil("updates started") { fake.started }
        fake.emitError(TestError.boom)
        let caught = await task.value
        XCTAssertEqual(caught as? MotionSourceError, .unavailable(.temporarilyUnavailable))
        await waitUntil("updates stopped after terminal error") { fake.stopped >= 1 }
    }

    /// Consume a stream expected to throw before yielding any element; return the error.
    private func firstError(
        from stream: AsyncThrowingStream<PedometerSample, Error>
    ) async -> Error? {
        do {
            for try await _ in stream { return nil }
            return nil
        } catch {
            return error
        }
    }
}

private enum TestError: Error { case boom }

/// A thread-safe sink for samples the consuming task collects off the stream.
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [PedometerSample] = []

    func append(_ sample: PedometerSample) {
        lock.lock()
        storage.append(sample)
        lock.unlock()
    }

    var samples: [PedometerSample] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
}
