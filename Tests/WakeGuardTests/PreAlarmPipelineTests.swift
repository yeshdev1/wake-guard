import XCTest

@testable import WakeGuard

/// Pre-alarm composition: the evaluation pipeline. Verifies it ties the E05 primitives — recent
/// movement (WG-081) → awake evidence + prompt policy (WG-080/082) → de-dup (WG-089) → prompt content
/// (WG-083): a recent walk in the lead window surfaces a prompt **once** (a second evaluation of the
/// same occurrence de-dups to nothing), while no movement or a disabled policy surfaces nothing. The
/// pipeline never mutates the alarm.
final class PreAlarmPipelineTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 901)
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func makeAlarm(preAlarm: PreAlarmPolicy) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule, preAlarmPolicy: preAlarm,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    private func makePipeline(steps: Int) -> PreAlarmPipeline {
        let sample = PedometerSample(
            timestamp: now.addingTimeInterval(-60), quality: .high, stepCount: steps,
            distanceMeters: nil, cadenceStepsPerSecond: nil, secondsSinceLastStep: nil)
        let query = RecentMovementQuery(
            source: FakeHistoricalPedometerSource(cannedSamples: [sample]))
        let coordinator = PreAlarmPromptCoordinator(ledger: InMemoryPreAlarmPromptLedger())
        return PreAlarmPipeline(movementQuery: query, coordinator: coordinator)
    }

    func testRecentWalkSurfacesAPromptOnce() async throws {
        let alarm = try makeAlarm(
            preAlarm: PreAlarmPolicy.enabled(
                leadTime: 600, allowedActions: [.turnOffToday, .remindLater]))
        let pipeline = makePipeline(steps: 40)
        let occurrence = now.addingTimeInterval(300)

        let first = await pipeline.evaluate(
            alarm: alarm, occurrence: occurrence, timeRemaining: 300, deviceInteracted: false,
            now: now)
        XCTAssertNotNil(first, "a recent walk in the lead window surfaces a prompt")
        XCTAssertEqual(first?.buttons.first?.action, .keep, "keep is the safe default")

        let second = await pipeline.evaluate(
            alarm: alarm, occurrence: occurrence, timeRemaining: 300, deviceInteracted: false,
            now: now)
        XCTAssertNil(second, "the same occurrence is not prompted twice (de-dup)")
    }

    func testNoMovementSurfacesNothing() async throws {
        let alarm = try makeAlarm(preAlarm: PreAlarmPolicy.enabled(leadTime: 600))
        let result = await makePipeline(steps: 0).evaluate(
            alarm: alarm, occurrence: now.addingTimeInterval(300), timeRemaining: 300,
            deviceInteracted: false, now: now)
        XCTAssertNil(result, "no movement → no prompt")
    }

    func testDisabledPreAlarmPolicySurfacesNothing() async throws {
        let alarm = try makeAlarm(preAlarm: .disabled)
        let result = await makePipeline(steps: 40).evaluate(
            alarm: alarm, occurrence: now.addingTimeInterval(300), timeRemaining: 300,
            deviceInteracted: false, now: now)
        XCTAssertNil(result, "pre-alarm disabled → no prompt even with recent movement")
    }
}
