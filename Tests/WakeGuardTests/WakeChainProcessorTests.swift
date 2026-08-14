import Foundation
import XCTest

@testable import WakeGuard

/// WG-291: the processor keeps the wake-chain family in step end-to-end (real in-memory Core Data +
/// the fake adapter): scheduling a critical challenge alarm places the family; a delete leaves no
/// re-rings behind; a valid pass sweeps the live family silent. Standard alarms are untouched.
final class WakeChainProcessorTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 293)

    private struct Fixture {
        let processor: AlarmCommandProcessor
        let adapter: FakeAlarmManagerAdapter
        let alarms: CoreDataAlarmRepository
        let satisfiedWakes: CoreDataSatisfiedWakeStore
    }

    private func makeFixture(now: Date) throws -> Fixture {
        let controller = try PersistenceController(inMemory: true)
        let alarms = CoreDataAlarmRepository(controller)
        let satisfiedWakes = CoreDataSatisfiedWakeStore(controller, now: { now })
        let processor = AlarmCommandProcessor(
            policy: FakeAlarmPolicyEngine(), alarms: alarms,
            audit: CoreDataAuditRepository(controller),
            outbox: CoreDataOutboxRepository(controller),
            alarmManager: fakeAdapter, clock: TestClock(now: now),
            ids: DeterministicIDGenerator(seed: 42), deviceTimeZone: { .gmt },
            satisfiedWakes: satisfiedWakes)
        return Fixture(
            processor: processor, adapter: fakeAdapter, alarms: alarms,
            satisfiedWakes: satisfiedWakes)
    }

    private let fakeAdapter = FakeAlarmManagerAdapter()

    private func makeAlarm(challenge: Bool = true) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule, criticality: .critical,
            challengePolicy: challenge ? .walk(try .standard()) : .none,
            createdAt: epoch, updatedAt: epoch)
    }

    private func iso(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    func testCreatePlacesTheFamilyBehindTheMainOccurrence() async throws {
        let fixture = try makeFixture(now: try iso("2026-08-17T04:00:00Z"))
        let alarm = try makeAlarm()

        let outcome = await fixture.processor.process(
            .create(alarm), from: .userInterface, by: .user)
        XCTAssertEqual(outcome, .applied)

        let requests = fixture.adapter.scheduledRequests
        XCTAssertEqual(
            requests.count, 1 + RearmConfiguration.default.maxAttempts,
            "the main occurrence and all 15 re-ring members are placed upfront")
        XCTAssertEqual(requests.filter { $0.parentAlarmID == alarm.id }.count, 15)
    }

    func testStandardChallengeFreeAlarmPlacesNoFamily() async throws {
        let fixture = try makeFixture(now: try iso("2026-08-17T04:00:00Z"))
        let alarm = try makeAlarm(challenge: false)
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        XCTAssertEqual(fixture.adapter.scheduledRequests.count, 1, "no chain without a challenge")
    }

    func testDeleteLeavesNoReRingsBehind() async throws {
        let fixture = try makeFixture(now: try iso("2026-08-17T04:00:00Z"))
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)

        _ = await fixture.processor.process(.delete(alarm.id), from: .userInterface, by: .user)

        let fire = try iso("2026-08-17T07:00:00Z")
        let members = WakeChain.memberIDs(for: alarm, occurrence: fire)
        let cancelled = Set(fixture.adapter.cancelledAlarmIDs)
        XCTAssertTrue(cancelled.contains(alarm.id), "the main occurrence is cancelled")
        for member in members {
            XCTAssertTrue(cancelled.contains(member), "every re-ring member is cancelled")
        }
    }

    func testAValidPassSweepsTheLiveFamilySilent() async throws {
        // 07:10 — mid ring window of the 07:00 fire.
        let fixture = try makeFixture(now: try iso("2026-08-17T07:10:00Z"))
        let alarm = try makeAlarm()
        try await fixture.alarms.save(alarm)

        _ = await fixture.processor.process(
            .markChallengePassed(alarm.id), from: .userInterface, by: .user)

        let fired = try iso("2026-08-17T07:00:00Z")
        let members = WakeChain.memberIDs(for: alarm, occurrence: fired)
        let stopped = Set(fixture.adapter.stoppedRingIDs)
        let cancelled = Set(fixture.adapter.cancelledAlarmIDs)
        XCTAssertTrue(stopped.contains(alarm.id), "the pass stops the main ring (#24)")
        for member in members {
            XCTAssertTrue(
                stopped.contains(member) || cancelled.contains(member),
                "every member is silenced — stopped if alerting, cancelled if scheduled")
        }
    }

    func testAValidPassRecordsTheSatisfiedWakeForTheLockFailsafe() async throws {
        // 07:10 — mid ring window of the 07:00 fire (WG-290).
        let fixture = try makeFixture(now: try iso("2026-08-17T07:10:00Z"))
        let alarm = try makeAlarm()
        try await fixture.alarms.save(alarm)
        let fired = try iso("2026-08-17T07:00:00Z")
        let before = await fixture.satisfiedWakes.isSatisfied(alarmID: alarm.id, fireTime: fired)
        XCTAssertFalse(before, "unsatisfied until the pass")

        _ = await fixture.processor.process(
            .markChallengePassed(alarm.id), from: .userInterface, by: .user)

        let after = await fixture.satisfiedWakes.isSatisfied(alarmID: alarm.id, fireTime: fired)
        XCTAssertTrue(
            after, "the pass persists the satisfied wake — the commitment lock's failsafe reads it")
        let otherOccurrence = await fixture.satisfiedWakes.isSatisfied(
            alarmID: alarm.id, fireTime: fired.addingTimeInterval(86_400))
        XCTAssertFalse(otherOccurrence, "satisfaction is per fire instant, not per alarm")
    }
}
