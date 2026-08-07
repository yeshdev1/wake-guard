import CoreMotion
import XCTest

@testable import WakeGuard

/// WG-064: the motion-activity adapter's mapping + streaming contract. The pure resolution
/// (`MotionActivityReading.resolvedKind` / `sample()`) is trace-tested — walking / stationary /
/// unknown map to domain values, ambiguity and no-flag resolve conservatively to `.unknown`, and
/// confidence + timestamps are retained. Availability degrades safely on unsupported / unauthorized
/// devices. The `CoreMotionActivityAdapter` is driven through a `FakeMotionActivityUpdates` seam to
/// verify it emits mapped samples, drops nil/invalid readings, and is cancellation-safe. The
/// CMMotionActivity mapping itself is device-only (real-device checklist / UAT CP-C).
final class MotionActivityTests: XCTestCase {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Conservative kind resolution (recorded readings)

    func testSingleFlagMapsToItsKind() {
        XCTAssertEqual(
            MotionActivityReading(timestamp: Self.base, quality: .high, walking: true).resolvedKind,
            .walking)
        XCTAssertEqual(
            MotionActivityReading(timestamp: Self.base, quality: .high, stationary: true)
                .resolvedKind, .stationary)
        XCTAssertEqual(
            MotionActivityReading(timestamp: Self.base, quality: .medium, running: true)
                .resolvedKind, .running)
        XCTAssertEqual(
            MotionActivityReading(timestamp: Self.base, quality: .low, automotive: true)
                .resolvedKind, .automotive)
    }

    func testAmbiguousNoneAndExplicitUnknownResolveToUnknown() {
        // No flag set at all.
        XCTAssertEqual(
            MotionActivityReading(timestamp: Self.base, quality: .high).resolvedKind, .unknown)
        // Multiple flags (a transition) — never reported as a confident single class.
        XCTAssertEqual(
            MotionActivityReading(
                timestamp: Self.base, quality: .high, walking: true, automotive: true
            ).resolvedKind,
            .unknown)
        // The classifier explicitly said unknown — dominates even if another flag is set.
        XCTAssertEqual(
            MotionActivityReading(
                timestamp: Self.base, quality: .high, walking: true, unknown: true
            )
            .resolvedKind, .unknown)
    }

    func testSampleRetainsConfidenceAndTimestamp() throws {
        let reading = MotionActivityReading(
            timestamp: Self.base, quality: .medium, walking: true)
        let sample = try XCTUnwrap(reading.sample())
        XCTAssertEqual(sample.quality, .medium)
        XCTAssertEqual(sample.timestamp, Self.base)
        XCTAssertEqual(sample.kind, .walking)
    }

    func testSampleDropsNonFiniteTimestamp() {
        let reading = MotionActivityReading(
            timestamp: Date(timeIntervalSince1970: .nan), quality: .high, stationary: true)
        XCTAssertNil(reading.sample())
    }

    // MARK: - Confidence mapping + availability degradation

    func testConfidenceMapsToQuality() {
        XCTAssertEqual(CMMotionActivityUpdates.quality(from: .low), .low)
        XCTAssertEqual(CMMotionActivityUpdates.quality(from: .medium), .medium)
        XCTAssertEqual(CMMotionActivityUpdates.quality(from: .high), .high)
    }

    func testAvailabilityDegradesSafely() {
        XCTAssertEqual(
            MotionSourceAvailability.forMotionActivity(
                activityAvailable: false, authorization: .authorized),
            .notPresent, "an unsupported device degrades to notPresent")
        XCTAssertEqual(
            MotionSourceAvailability.forMotionActivity(
                activityAvailable: true, authorization: .authorized), .available)
        XCTAssertEqual(
            MotionSourceAvailability.forMotionActivity(
                activityAvailable: true, authorization: .denied), .notAuthorized)
        XCTAssertEqual(
            MotionSourceAvailability.forMotionActivity(
                activityAvailable: true, authorization: .notDetermined), .notAuthorized)
        XCTAssertEqual(
            MotionSourceAvailability.forMotionActivity(
                activityAvailable: true, authorization: .restricted), .restricted)
    }

    // MARK: - Adapter streaming (recorded trace through the seam)

    private func makeAdapter(
        _ updates: MotionActivityUpdates, availability: MotionSourceAvailability = .available
    ) -> CoreMotionActivityAdapter {
        CoreMotionActivityAdapter(updates: updates, availabilityProvider: { availability })
    }

    private func waitUntil(_ message: String, _ condition: @Sendable () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("timed out waiting: \(message)")
    }

    func testEmitsMappedSamplesAndDropsNilOrInvalid() async {
        let fake = FakeMotionActivityUpdates()
        let adapter = makeAdapter(fake)
        let collector = Collector()
        let task = Task {
            for try await sample in adapter.samples() { collector.append(sample) }
        }
        await waitUntil("updates started") { fake.started }

        fake.emit(MotionActivityReading(timestamp: Self.base, quality: .high, walking: true))
        fake.emit(nil)  // nil reading -> ignored
        fake.emit(
            MotionActivityReading(
                timestamp: Date(timeIntervalSince1970: .nan), quality: .low, stationary: true))
        fake.emit(
            MotionActivityReading(
                timestamp: Self.base.addingTimeInterval(1), quality: .medium, stationary: true))

        await waitUntil("two samples collected") { collector.count == 2 }
        task.cancel()
        _ = await task.result

        XCTAssertEqual(collector.samples.map(\.kind), [.walking, .stationary])
        XCTAssertEqual(collector.samples.map(\.quality), [.high, .medium])
        XCTAssertGreaterThanOrEqual(fake.stopped, 1, "cancellation stops updates")
    }

    func testCancellationStopsUpdates() async {
        let fake = FakeMotionActivityUpdates()
        let adapter = makeAdapter(fake)
        let task = Task { for try await _ in adapter.samples() {} }
        await waitUntil("updates started") { fake.started }
        task.cancel()
        _ = await task.result
        await waitUntil("updates stopped on cancellation") { fake.stopped >= 1 }
    }

    func testUnavailableStreamThrowsWithoutStarting() async {
        let fake = FakeMotionActivityUpdates()
        let adapter = makeAdapter(fake, availability: .notPresent)
        let caught = await firstError(from: adapter.samples())
        XCTAssertEqual(caught as? MotionSourceError, .unavailable(.notPresent))
        XCTAssertFalse(fake.started, "an unavailable source must not start CoreMotion updates")
        XCTAssertEqual(fake.stopped, 0)
    }

    /// A low-confidence walking reading must reach the consumer un-dropped and with `quality`
    /// intact — the adapter must never gate on confidence (WG-068/069 own the pass threshold).
    /// Locks the anti-cheat contract against a future "helpful" confidence filter here.
    func testLowConfidenceWalkingSurvivesUngated() async {
        let fake = FakeMotionActivityUpdates()
        let adapter = makeAdapter(fake)
        let collector = Collector()
        let task = Task {
            for try await sample in adapter.samples() { collector.append(sample) }
        }
        await waitUntil("updates started") { fake.started }
        fake.emit(MotionActivityReading(timestamp: Self.base, quality: .low, walking: true))
        await waitUntil("one sample collected") { collector.count == 1 }
        task.cancel()
        _ = await task.result
        XCTAssertEqual(collector.samples.first?.kind, .walking)
        XCTAssertEqual(collector.samples.first?.quality, .low, "confidence must not be gated away")
    }

    /// A late CoreMotion callback after teardown must be a safe no-op — the manager's `stop` is
    /// exactly-once, but a callback already in flight can still fire; yielding it post-finish must
    /// be dropped, never delivered or crash.
    func testReadingAfterCancellationIsDropped() async {
        let fake = FakeMotionActivityUpdates()
        let adapter = makeAdapter(fake)
        let collector = Collector()
        let task = Task {
            for try await sample in adapter.samples() { collector.append(sample) }
        }
        await waitUntil("updates started") { fake.started }
        fake.emit(MotionActivityReading(timestamp: Self.base, quality: .high, walking: true))
        await waitUntil("first sample collected") { collector.count == 1 }
        task.cancel()
        _ = await task.result
        // Deliver a reading *after* the stream has torn down.
        fake.emit(
            MotionActivityReading(
                timestamp: Self.base.addingTimeInterval(1), quality: .high, walking: true))
        await Task.yield()
        XCTAssertEqual(
            collector.count, 1, "a reading delivered after cancellation must not be yielded")
    }

    private func firstError(
        from stream: AsyncThrowingStream<MotionActivitySample, Error>
    ) async -> Error? {
        do {
            for try await _ in stream { return nil }
            return nil
        } catch {
            return error
        }
    }
}

/// A thread-safe sink for samples the consuming task collects off the stream.
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [MotionActivitySample] = []

    func append(_ sample: MotionActivitySample) {
        lock.lock()
        storage.append(sample)
        lock.unlock()
    }

    var samples: [MotionActivitySample] {
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
