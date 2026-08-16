import Foundation
import XCTest

@testable import WakeGuard

/// WG-130: partial / denied / revoked HealthKit access. Verifies **every permission state has the
/// expected UI** (granted/partial → an available readiness, everything else → the "not enough data"
/// state), that **revocation does not crash calculations** (an empty/throwing query degrades to
/// unavailable), and that **no stale claim remains** (readiness is recomputed each refresh, so a
/// revocation replaces any prior value).
@MainActor
final class HealthAccessStatesTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// One night's asleep interval, `dayOffset` days before `base`.
    private func night(dayOffset: Int, asleepHours: Double = 7) -> [SleepSample] {
        let start = base.addingTimeInterval(Double(dayOffset) * 86_400)
        return [
            SleepSample(
                category: .asleep,
                interval: DateInterval(
                    start: start, end: start.addingTimeInterval(asleepHours * 3_600)))
        ]
    }

    private func viewModel(_ source: MutableSleepSource) -> ReadinessViewModel {
        ReadinessViewModel(sleepQuery: source, calendar: makeCalendar())
    }

    // MARK: every permission state has expected UI

    func testEveryAccessSummaryMapsToExpectedReadinessAvailability() {
        let coordinator = HealthAuthorizationCoordinator(
            provider: RecordingHealthAuthorizationProvider())
        XCTAssertTrue(coordinator.isReadinessAvailable(.granted))
        XCTAssertTrue(coordinator.isReadinessAvailable(.partial))
        for summary in [HealthAccessSummary.unavailable, .notDetermined, .denied] {
            XCTAssertFalse(
                coordinator.isReadinessAvailable(summary),
                "\(summary) → the unavailable (‘not enough data’) UI")
        }
    }

    func testGrantedAccessWithDataProducesAnAvailableReadiness() async throws {
        let model = viewModel(MutableSleepSource(night(dayOffset: -1) + night(dayOffset: -2)))
        await model.refresh(now: base)
        let assessment = try XCTUnwrap(model.assessment)
        XCTAssertFalse(assessment.factors.isEmpty)
        XCTAssertNotNil(assessment.level)
    }

    func testDeniedAccessShowsTheUnavailableUI() async throws {
        // Denied/revoked HealthKit → the query returns no samples.
        let model = viewModel(MutableSleepSource([]))
        await model.refresh(now: base)
        let assessment = try XCTUnwrap(model.assessment)
        XCTAssertTrue(assessment.factors.isEmpty)
        XCTAssertNil(assessment.level)
        XCTAssertTrue(
            ReadinessExplanation.from(assessment).summary.lowercased().contains(
                "isn't enough sleep data"),
            "the readiness card shows the honest ‘not enough data’ state")
    }

    // MARK: revocation does not crash calculations

    func testAThrowingQueryDegradesWithoutCrashing() async throws {
        let source = MutableSleepSource(night(dayOffset: -1))
        source.shouldThrow = true  // access revoked mid-flight → the query errors
        let model = viewModel(source)
        await model.refresh(now: base)
        XCTAssertTrue(
            try XCTUnwrap(model.assessment).factors.isEmpty, "no crash; degrades to unavailable")
    }

    func testTheCalculatorsDoNotCrashOnRevokedEmptyData() {
        XCTAssertNil(SleepMetrics.asleepDuration([]))
        XCTAssertNil(SleepMetrics.consistency(ofLocalSeconds: []))
        XCTAssertNil(SleepDebt.estimate(nightlyDurations: [], need: .default))
        XCTAssertTrue(
            ReadinessComputer.readiness(from: [], need: .default, calendar: makeCalendar())
                .factors.isEmpty)
    }

    // MARK: no stale claims remain

    func testRefreshAfterRevocationLeavesNoStaleReadiness() async throws {
        let source = MutableSleepSource(night(dayOffset: -1) + night(dayOffset: -2))
        let model = viewModel(source)
        await model.refresh(now: base)
        XCTAssertFalse(try XCTUnwrap(model.assessment).factors.isEmpty, "available with data")

        source.samples = []  // access revoked — data is gone
        await model.refresh(now: base)
        let after = try XCTUnwrap(model.assessment)
        XCTAssertTrue(after.factors.isEmpty, "the prior readiness is cleared — no stale claim")
        XCTAssertNil(after.level)
    }

    // MARK: the computer groups nights + degrades on partial data

    func testComputerGroupsNightsByGapAndHandlesPartialData() {
        XCTAssertEqual(
            ReadinessComputer.nights(from: night(dayOffset: -1) + night(dayOffset: -3)).count, 2,
            "a >6h gap starts a new night")
        // A single night → duration + debt factors but no consistency (needs ≥2 nights) → moderate.
        let single = ReadinessComputer.readiness(
            from: night(dayOffset: -1, asleepHours: 7), need: .default, calendar: makeCalendar())
        XCTAssertEqual(Set(single.factors.map(\.kind)), [.sleepDuration, .sleepDebt])
        XCTAssertEqual(single.certainty, .moderate)
    }

    // MARK: last night's interruptions (WG-309)

    func testLastNightInterruptionsUsesTheMostRecentNightAndSurfacesInTheViewModel() async throws {
        // An earlier undisturbed night plus a most-recent night with one mid-sleep awakening. "Last night"
        // must reflect the recent night's interruption, not the older slept-through one.
        let lastNightStart = base.addingTimeInterval(-1 * 86_400)
        let disturbedLastNight = [
            SleepSample(
                category: .asleep,
                interval: DateInterval(
                    start: lastNightStart, end: lastNightStart.addingTimeInterval(3_600))),
            SleepSample(
                category: .awake,
                interval: DateInterval(
                    start: lastNightStart.addingTimeInterval(3_600),
                    end: lastNightStart.addingTimeInterval(4_200))),  // 10 min awake
            SleepSample(
                category: .asleep,
                interval: DateInterval(
                    start: lastNightStart.addingTimeInterval(4_200),
                    end: lastNightStart.addingTimeInterval(10_800))),
        ]
        let samples = night(dayOffset: -3) + disturbedLastNight
        XCTAssertEqual(
            ReadinessComputer.lastNightInterruptions(from: samples),
            SleepInterruptions(awakenings: 1, totalAwake: 600))

        let model = viewModel(MutableSleepSource(samples))
        await model.refresh(now: base)
        XCTAssertEqual(
            model.lastNightInterruptions, SleepInterruptions(awakenings: 1, totalAwake: 600),
            "the view model surfaces last night's interruptions")
    }

    func testLastNightInterruptionsUnavailableWithNoSleepData() {
        XCTAssertNil(
            ReadinessComputer.lastNightInterruptions(from: []),
            "no sleep data → unavailable, not fabricated")
    }

    // MARK: motion-based disturbance fallback (WG-310)

    func testMotionFallbackEstimatesDisturbancesWhenHealthKitHasNoSleepData() async throws {
        // No HealthKit sleep data (no Watch), but motion history shows one overnight walk.
        let motion = FixedMotionHistory([
            MotionActivitySample(
                timestamp: base.addingTimeInterval(-3_600), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: base.addingTimeInterval(-1_800), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: base.addingTimeInterval(-1_200), quality: .high, kind: .stationary),
        ])
        let model = ReadinessViewModel(
            sleepQuery: MutableSleepSource([]), motionHistory: motion, calendar: makeCalendar())
        await model.refresh(now: base)
        XCTAssertNil(model.lastNightInterruptions, "no HealthKit sleep data")
        XCTAssertEqual(
            model.estimatedDisturbances, SleepDisturbances(pickups: 1, movingDuration: 600),
            "the motion fallback estimates the overnight disturbance")
    }

    func testMotionFallbackIsSuppressedWhenHealthKitHasSleepData() async throws {
        let motion = FixedMotionHistory([
            MotionActivitySample(
                timestamp: base.addingTimeInterval(-1_800), quality: .high, kind: .walking)
        ])
        let model = ReadinessViewModel(
            sleepQuery: MutableSleepSource(night(dayOffset: -1)), motionHistory: motion,
            calendar: makeCalendar())
        await model.refresh(now: base)
        XCTAssertNotNil(
            model.lastNightInterruptions, "HealthKit answered → interruptions available")
        XCTAssertNil(
            model.estimatedDisturbances, "the motion fallback is suppressed when HealthKit has data"
        )
    }
}

private final class MutableSleepSource: SleepSampleQuerying, @unchecked Sendable {
    var samples: [SleepSample]
    var shouldThrow = false
    init(_ samples: [SleepSample] = []) { self.samples = samples }
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        if shouldThrow { throw CancellationError() }
        return samples
    }
}

private struct FixedMotionHistory: MotionActivityHistorySource {
    let samples: [MotionActivitySample]
    init(_ samples: [MotionActivitySample]) { self.samples = samples }
    func activitySamples(in window: DateInterval) async throws -> [MotionActivitySample] { samples }
}
