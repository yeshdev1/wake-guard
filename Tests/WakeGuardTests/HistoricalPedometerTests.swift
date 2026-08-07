import CoreMotion
import XCTest

@testable import WakeGuard

/// WG-062: the historical pedometer query pieces. Verifies the query window validates its interval
/// and timestamps (ordered, not future, bounded), that the sample validation (WG-060's deferred
/// check) rejects impossible readings, that availability maps hardware + authorization, that
/// CoreMotion's status maps to the domain, and that an unavailable source throws (never silently
/// empty). The CMPedometer adapter itself is device-only.
final class HistoricalPedometerTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Query window validation

    func testValidWindowConstructs() throws {
        let window = try PedometerQueryWindow(
            start: now.addingTimeInterval(-3600), end: now, now: now)
        XCTAssertEqual(window.end, now)
    }

    func testWindowRejectsStartNotBeforeEnd() {
        XCTAssertThrowsError(try PedometerQueryWindow(start: now, end: now, now: now))
        XCTAssertThrowsError(
            try PedometerQueryWindow(start: now, end: now.addingTimeInterval(-1), now: now))
    }

    func testWindowRejectsFutureEnd() {
        XCTAssertThrowsError(
            try PedometerQueryWindow(start: now, end: now.addingTimeInterval(60), now: now))
    }

    func testWindowRejectsOverlongSpan() {
        XCTAssertThrowsError(
            try PedometerQueryWindow(
                start: now.addingTimeInterval(-2 * 24 * 3600), end: now, now: now))
    }

    func testWindowRejectsNonFiniteDates() {
        let nan = Date(timeIntervalSince1970: .nan)
        // A NaN clock must not slip past the future guard — `end <= now` is NaN-blind, so a
        // non-finite `now` would otherwise legitimize a future/garbage-bounded read (review B1).
        XCTAssertThrowsError(
            try PedometerQueryWindow(start: now.addingTimeInterval(-3600), end: now, now: nan))
        XCTAssertThrowsError(try PedometerQueryWindow(start: nan, end: now, now: now))
        XCTAssertThrowsError(
            try PedometerQueryWindow(start: now.addingTimeInterval(-60), end: nan, now: now))
    }

    // MARK: - Sample validation (WG-060's deferred check, landing at the boundary)

    func testValidatedSampleAcceptsPlausibleValues() throws {
        let sample = try PedometerSample.validated(
            timestamp: now, quality: .high, stepCount: 12, distanceMeters: 9.0,
            cadenceStepsPerSecond: 1.4)
        XCTAssertEqual(sample.stepCount, 12)
    }

    func testValidatedSampleRejectsNegativeSteps() {
        XCTAssertThrowsError(
            try PedometerSample.validated(timestamp: now, quality: .high, stepCount: -1))
    }

    func testValidatedSampleRejectsNonFiniteOrNegativeMeasures() {
        XCTAssertThrowsError(
            try PedometerSample.validated(
                timestamp: now, quality: .high, stepCount: 1, distanceMeters: .nan))
        XCTAssertThrowsError(
            try PedometerSample.validated(
                timestamp: now, quality: .high, stepCount: 1, cadenceStepsPerSecond: -0.5))
    }

    func testValidatedSampleRejectsNonFiniteTimestamp() {
        XCTAssertThrowsError(
            try PedometerSample.validated(
                timestamp: Date(timeIntervalSince1970: .nan), quality: .high, stepCount: 1))
    }

    func testValidatedSampleRejectsTimestampOutsideWindow() throws {
        let window = try PedometerQueryWindow(
            start: now.addingTimeInterval(-3600), end: now, now: now)
        // Past the window end → a future-stamped aggregate (false "just moved").
        XCTAssertThrowsError(
            try PedometerSample.validated(
                timestamp: now.addingTimeInterval(1), quality: .high, stepCount: 5, within: window))
        // Before the window start.
        XCTAssertThrowsError(
            try PedometerSample.validated(
                timestamp: now.addingTimeInterval(-7200), quality: .high, stepCount: 5,
                within: window))
        // Inside the window → accepted.
        let inside = try PedometerSample.validated(
            timestamp: now.addingTimeInterval(-60), quality: .high, stepCount: 5, within: window)
        XCTAssertEqual(inside.stepCount, 5)
    }

    // MARK: - Availability + status mapping

    func testAvailabilityMapsHardwareAndAuthorization() {
        XCTAssertEqual(
            MotionSourceAvailability.forPedometer(
                stepCountingAvailable: false, authorization: .authorized),
            .notPresent, "absent hardware dominates a grant")
        XCTAssertEqual(
            MotionSourceAvailability.forPedometer(
                stepCountingAvailable: true, authorization: .authorized), .available)
        XCTAssertEqual(
            MotionSourceAvailability.forPedometer(
                stepCountingAvailable: true, authorization: .denied), .notAuthorized)
        XCTAssertEqual(
            MotionSourceAvailability.forPedometer(
                stepCountingAvailable: true, authorization: .notDetermined), .notAuthorized)
        XCTAssertEqual(
            MotionSourceAvailability.forPedometer(
                stepCountingAvailable: true, authorization: .restricted), .restricted)
    }

    func testCoreMotionAuthorizationStatusMapsToDomain() {
        XCTAssertEqual(CoreMotionHistoricalPedometerAdapter.map(.authorized), .authorized)
        XCTAssertEqual(CoreMotionHistoricalPedometerAdapter.map(.denied), .denied)
        XCTAssertEqual(CoreMotionHistoricalPedometerAdapter.map(.restricted), .restricted)
        XCTAssertEqual(CoreMotionHistoricalPedometerAdapter.map(.notDetermined), .notDetermined)
    }

    // MARK: - Port behavior via the fake

    func testUnavailableSourceThrows() async throws {
        let source = FakeHistoricalPedometerSource(availabilityState: .notAuthorized)
        let window = try PedometerQueryWindow(
            start: now.addingTimeInterval(-60), end: now, now: now)
        do {
            _ = try await source.samples(in: window)
            XCTFail("an unavailable source must throw, not return empty")
        } catch let error as MotionSourceError {
            XCTAssertEqual(error, .unavailable(.notAuthorized))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
