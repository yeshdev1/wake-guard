import Foundation
import XCTest

@testable import WakeGuard

/// WG-123: sleep-duration and consistency. Verifies the **formulas are transparent and unit-tested**
/// (asleep = sum of asleep intervals; consistency = circular mean + mean deviation of local midpoints),
/// that **missing data returns unavailable (`nil`), never a fabricated value**, and that **time-zone
/// changes are covered** — durations are absolute elapsed time (DST-safe) and consistency is measured in
/// each night's local time-of-day (so a stable local bedtime stays consistent across travel; midnight
/// wraparound is handled).
final class SleepMetricsTests: XCTestCase {

    // swiftlint:disable:next function_parameter_count
    private func makeDate(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in identifier: String
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
        var components = DateComponents()
        (components.year, components.month, components.day) = (year, month, day)
        (components.hour, components.minute, components.second) = (hour, minute, 0)
        return try XCTUnwrap(calendar.date(from: components))
    }

    private func asleep(_ start: Date, _ end: Date) -> SleepSample {
        SleepSample(category: .asleep, interval: DateInterval(start: start, end: end))
    }

    // MARK: asleep duration

    func testAsleepDurationSumsOnlyAsleepIntervals() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            SleepSample(
                category: .inBed,
                interval: DateInterval(start: base, end: base.addingTimeInterval(3_600))),
            asleep(base.addingTimeInterval(600), base.addingTimeInterval(3_600)),  // 50 min
            SleepSample(
                category: .awake,
                interval: DateInterval(
                    start: base.addingTimeInterval(3_600), end: base.addingTimeInterval(3_900))),
        ]
        // Only the 50-minute asleep interval counts — inBed and awake are excluded.
        XCTAssertEqual(try XCTUnwrap(SleepMetrics.asleepDuration(samples)), 3_000)
    }

    func testAsleepDurationIsUnavailableWithoutAsleepSamples() {
        XCTAssertNil(SleepMetrics.asleepDuration([]), "missing data → unavailable, never 0")
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let inBedOnly = [
            SleepSample(
                category: .inBed,
                interval: DateInterval(start: base, end: base.addingTimeInterval(3_600)))
        ]
        XCTAssertNil(SleepMetrics.asleepDuration(inBedOnly))
    }

    func testAsleepDurationIsAbsoluteElapsedAcrossADSTSpringForward() throws {
        // 01:00 EST → 03:00 EDT on the spring-forward night: the wall clock spans 2 h but only 1 h
        // actually elapses (02:00–02:59 doesn't exist). Duration is the real elapsed hour — DST-safe.
        let start = try makeDate(2026, 3, 8, 1, 0, in: "America/New_York")
        let end = try makeDate(2026, 3, 8, 3, 0, in: "America/New_York")
        XCTAssertEqual(try XCTUnwrap(SleepMetrics.asleepDuration([asleep(start, end)])), 3_600)
    }

    // MARK: midpoint + local time-of-day (zone-aware)

    func testSleepMidpointIsTheAbsoluteCentreOfTheAsleepSpan() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let midpoint = SleepMetrics.sleepMidpoint([asleep(base, base.addingTimeInterval(3_600))])
        XCTAssertEqual(midpoint, base.addingTimeInterval(1_800))
    }

    func testLocalSecondsOfDayIsZoneAware() throws {
        // The SAME instant reads as a different local time-of-day in different zones — the basis for
        // covering travel (each night uses its own zone).
        let instant = try makeDate(2026, 6, 15, 23, 0, in: "America/New_York")
        XCTAssertEqual(
            SleepMetrics.localSecondsOfDay(
                instant, in: try XCTUnwrap(TimeZone(identifier: "America/New_York"))),
            23 * 3_600)
        XCTAssertEqual(
            SleepMetrics.localSecondsOfDay(
                instant, in: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))),
            12 * 3_600)  // 23:00 EDT = 12:00 the next day in Tokyo
    }

    // MARK: consistency

    func testConsistencyIsUnavailableForFewerThanTwoNights() {
        XCTAssertNil(SleepMetrics.consistency(ofLocalSeconds: []))
        XCTAssertNil(SleepMetrics.consistency(ofLocalSeconds: [3_600]))
    }

    func testIdenticalMidpointsAreMaximallyConsistent() throws {
        let result = try XCTUnwrap(SleepMetrics.consistency(ofLocalSeconds: [82_800, 82_800]))
        XCTAssertEqual(result.typicalMidpointSecondsOfDay, 82_800)
        XCTAssertEqual(result.meanDeviationMinutes, 0, accuracy: 0.001)
        XCTAssertEqual(result.nights, 2)
    }

    func testConsistencyHandlesMidnightWraparound() throws {
        // 23:50 (85 800 s) and 00:10 (600 s) are 20 min apart, not ~24 h — circular stats, typical ≈ 00:00.
        let result = try XCTUnwrap(SleepMetrics.consistency(ofLocalSeconds: [85_800, 600]))
        XCTAssertEqual(result.typicalMidpointSecondsOfDay, 0, "typical midpoint ≈ midnight")
        XCTAssertEqual(result.meanDeviationMinutes, 10, accuracy: 0.01)
    }

    func testAStableLocalBedtimeStaysConsistentAcrossTravel() throws {
        // Two nights, both a 23:00 LOCAL midpoint but in different zones (a trip). Computing each night's
        // midpoint in its own zone yields the same local seconds → maximally consistent, not wrecked.
        let home = try makeDate(2026, 6, 15, 23, 0, in: "America/New_York")
        let away = try makeDate(2026, 7, 20, 23, 0, in: "Asia/Tokyo")
        let localSeconds = [
            SleepMetrics.localSecondsOfDay(
                home, in: try XCTUnwrap(TimeZone(identifier: "America/New_York"))),
            SleepMetrics.localSecondsOfDay(
                away, in: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))),
        ]
        let result = try XCTUnwrap(SleepMetrics.consistency(ofLocalSeconds: localSeconds))
        XCTAssertEqual(result.typicalMidpointSecondsOfDay, 23 * 3_600)
        XCTAssertEqual(result.meanDeviationMinutes, 0, accuracy: 0.001)
    }
}
