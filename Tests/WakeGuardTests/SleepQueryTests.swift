import Foundation
import XCTest

@testable import WakeGuard

/// WG-122: the sleep-analysis query. Verifies **sleep categories map correctly** (HealthKit raw values →
/// domain categories, unknown → skipped), **overlapping samples are handled** (multi-source union,
/// awake-wins, inBed/asleep priority, adjacent merge, zero-duration dropped), and that queries are
/// **bounded** (clamped window) and **cancelable** (the async contract propagates cancellation).
final class SleepQueryTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }
    private func asleep(_ from: Double, _ to: Double) -> SleepSample {
        SleepSample(category: .asleep, interval: DateInterval(start: at(from), end: at(to)))
    }
    private func sample(_ category: SleepCategory, _ from: Double, _ to: Double) -> SleepSample {
        SleepSample(category: category, interval: DateInterval(start: at(from), end: at(to)))
    }

    // MARK: sleep categories map correctly

    func testHealthKitSleepValuesMapToDomainCategories() {
        XCTAssertEqual(SleepCategory(healthKitSleepValue: 0), .inBed)
        XCTAssertEqual(SleepCategory(healthKitSleepValue: 1), .asleep)  // asleepUnspecified
        XCTAssertEqual(SleepCategory(healthKitSleepValue: 2), .awake)
        XCTAssertEqual(SleepCategory(healthKitSleepValue: 3), .asleep)  // asleepCore
        XCTAssertEqual(SleepCategory(healthKitSleepValue: 4), .asleep)  // asleepDeep
        XCTAssertEqual(SleepCategory(healthKitSleepValue: 5), .asleep)  // asleepREM
    }

    func testUnknownSleepValueIsSkippedFailClosed() {
        for value in [-1, 6, 99] {
            XCTAssertNil(
                SleepCategory(healthKitSleepValue: value),
                "unknown value \(value) must not miscount")
        }
    }

    // MARK: overlapping samples are handled

    func testOverlapPrioritiesAreDistinct() {
        // The normalizer resolves ties by (priority, rawValue), but its intent is that each category has a
        // distinct priority (equal priority ⟺ equal category). Enforce it so a future stage can't silently
        // make the overlap winner order-dependent.
        let priorities = SleepCategory.allCases.map(\.overlapPriority)
        XCTAssertEqual(
            Set(priorities).count, priorities.count, "each category needs a distinct priority")
    }

    func testEmptyAndSingleAndZeroDuration() {
        XCTAssertEqual(SleepTimeline.normalize([]), [])
        XCTAssertEqual(SleepTimeline.normalize([asleep(0, 60)]), [asleep(0, 60)])
        // A zero-duration sample contributes nothing and is dropped.
        let zero = SleepSample(
            category: .asleep, interval: DateInterval(start: at(100), end: at(100)))
        XCTAssertEqual(SleepTimeline.normalize([zero, asleep(0, 60)]), [asleep(0, 60)])
    }

    func testOverlappingSameCategoryFromTwoSourcesMergesToAUnion() {
        // Two sources (phone + watch) each report asleep, overlapping — must not double-count.
        XCTAssertEqual(
            SleepTimeline.normalize([asleep(0, 300), asleep(240, 540)]), [asleep(0, 540)])
    }

    func testDuplicateSamplesDeduplicate() {
        XCTAssertEqual(SleepTimeline.normalize([asleep(0, 300), asleep(0, 300)]), [asleep(0, 300)])
    }

    func testAsleepWinsOverInBedWithinTheBedSpan() {
        // An inBed span wrapping an asleep sub-interval → asleep in the middle, inBed on the edges.
        let result = SleepTimeline.normalize([sample(.inBed, 0, 480), asleep(60, 420)])
        XCTAssertEqual(
            result, [sample(.inBed, 0, 60), asleep(60, 420), sample(.inBed, 420, 480)])
    }

    func testAwakeWinsOverOverlappingAsleep() {
        // A source reporting awake during an asleep span → awake for the overlap (you're not asleep then).
        let result = SleepTimeline.normalize([asleep(0, 480), sample(.awake, 200, 260)])
        XCTAssertEqual(
            result, [asleep(0, 200), sample(.awake, 200, 260), asleep(260, 480)])
    }

    func testAdjacentSameCategoryRunsMerge() {
        XCTAssertEqual(
            SleepTimeline.normalize([asleep(0, 120), asleep(120, 240)]), [asleep(0, 240)])
    }

    // MARK: queries are bounded

    func testWindowClampsAnOverlyOldRequestToTheMaxLookback() {
        let end = at(0)
        let window = SleepQueryWindow(end: end, requestedStart: at(-100_000))
        XCTAssertEqual(window.start, end.addingTimeInterval(-SleepQueryWindow.defaultMaxLookback))
        XCTAssertEqual(window.end, end)
        XCTAssertFalse(window.isEmpty)
    }

    func testWindowKeepsARecentRequestedStart() {
        let end = at(0)
        let window = SleepQueryWindow(end: end, requestedStart: at(-60))  // 1 h ago
        XCTAssertEqual(window.start, at(-60))
        XCTAssertEqual(window.duration, 3_600)
    }

    func testWindowForARequestAfterEndIsEmpty() {
        let end = at(0)
        let window = SleepQueryWindow(end: end, requestedStart: at(60))
        XCTAssertTrue(window.isEmpty)
    }

    // MARK: queries are cancelable

    func testASleepSourceHonorsTaskCancellation() async {
        let (source, start, end) = (CancellableSleepSource(), t0, at(60))
        let task = Task { try await source.sleepSamples(from: start, to: end) }
        task.cancel()
        let result = await task.result
        if case .success = result {
            XCTFail("a cancelled sleep query must throw, not return a value")
        }
    }
}

/// A `SleepSampleQuerying` whose work is cancellable — used to prove the port's async contract propagates
/// task cancellation (the real adapter stops its `HKSampleQuery` on cancel; device-verified).
private struct CancellableSleepSource: SleepSampleQuerying {
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        try await Task.sleep(for: .seconds(10))
        return []
    }
}
