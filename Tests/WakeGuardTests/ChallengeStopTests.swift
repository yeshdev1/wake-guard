import XCTest

@testable import WakeGuard

/// WG-073: connecting a valid challenge pass to the authorized ring-stop. Verifies that
/// `markChallengePassed` stops the ring through the adapter and audits the result, that duplicate /
/// racing passes are idempotent (the outbox dedups; the coordinator emits one stop), that only a
/// terminal pass or the accessible fallback emits a stop, and that uncertain / failed stops surface
/// correctly (#10, #24).
final class ChallengeStopTests: XCTestCase {

    private let alarmIDs = DeterministicIDGenerator(seed: 73)

    private struct Fixture {
        let processor: AlarmCommandProcessor
        let alarms: CoreDataAlarmRepository
        let audit: CoreDataAuditRepository
        let adapter: FakeAlarmManagerAdapter
    }

    private func makeFixture() throws -> Fixture {
        let controller = try PersistenceController(inMemory: true)
        let adapter = FakeAlarmManagerAdapter()
        let alarms = CoreDataAlarmRepository(controller)
        let audit = CoreDataAuditRepository(controller)
        let processor = AlarmCommandProcessor(
            policy: FakeAlarmPolicyEngine(decision: .authorized), alarms: alarms, audit: audit,
            outbox: CoreDataOutboxRepository(controller), alarmManager: adapter,
            clock: TestClock(now: Date(timeIntervalSince1970: 1_000_000)),
            ids: DeterministicIDGenerator(seed: 27), deviceTimeZone: { .gmt })
        return Fixture(processor: processor, alarms: alarms, audit: audit, adapter: adapter)
    }

    private func makeAlarm() throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(alarmIDs.next()), label: "wake", isEnabled: true, schedule: schedule,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    // MARK: - Processor: markChallengePassed → stop + audit

    func testValidPassStopsRingAndAudits() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)

        let outcome = await fixture.processor.process(
            .markChallengePassed(alarm.id), from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(fixture.adapter.stoppedRingIDs, [alarm.id], "the ring is stopped")
        let events = try await fixture.audit.events(forAlarm: alarm.id)
        XCTAssertEqual(events.last?.command, .markChallengePassed(alarm.id))
        XCTAssertEqual(events.last?.outcome, .succeeded, "the stop is audited")
    }

    func testDuplicatePassIsIdempotent() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)

        for _ in 0..<3 {
            _ = await fixture.processor.process(
                .markChallengePassed(alarm.id), from: .userInterface, by: .user)
        }
        XCTAssertEqual(
            fixture.adapter.stoppedRingIDs, [alarm.id],
            "the outbox dedups — the adapter stops the ring exactly once")
    }

    func testPassForMissingAlarmIsNoOp() async throws {
        let fixture = try makeFixture()
        let missing = AlarmID(alarmIDs.next())
        let outcome = await fixture.processor.process(
            .markChallengePassed(missing), from: .userInterface, by: .user)
        XCTAssertEqual(outcome, .noOp)
        XCTAssertTrue(fixture.adapter.stoppedRingIDs.isEmpty, "nothing to stop")
    }

    func testUncertainStopSurfacesUncertain() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        fixture.adapter.inject(.uncertain, on: .stopRing)

        let outcome = await fixture.processor.process(
            .markChallengePassed(alarm.id), from: .userInterface, by: .user)
        XCTAssertEqual(outcome, .uncertain, "an uncertain stop is never assumed done")
        let events = try await fixture.audit.events(forAlarm: alarm.id)
        XCTAssertEqual(
            events.last?.outcome, .failed, "an uncertain stop is not recorded as 'stopped'")
    }

    func testFailedStopAuditsFailure() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        fixture.adapter.inject(.failed(reason: "system busy"), on: .stopRing)

        let outcome = await fixture.processor.process(
            .markChallengePassed(alarm.id), from: .userInterface, by: .user)
        guard case .failed = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        let events = try await fixture.audit.events(forAlarm: alarm.id)
        XCTAssertEqual(events.last?.outcome, .failed)
    }

    // MARK: - Coordinator: only a valid pass emits a stop, once

    func testWalkPassSubmitsStopOnce() async {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let id = AlarmID(alarmIDs.next())
        let coordinator = ChallengeStopCoordinator(alarmID: id, processor: processor)
        _ = await coordinator.walkChallengeReached(.passed)
        XCTAssertEqual(processor.seen, [.markChallengePassed(id)])
    }

    func testNonPassPhaseNeverSubmits() async {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let coordinator = ChallengeStopCoordinator(
            alarmID: AlarmID(alarmIDs.next()), processor: processor)
        for phase in [
            WakeChallengePhase.idle, .starting, .active, .failed, .timedOut, .unavailable,
        ] {
            _ = await coordinator.walkChallengeReached(phase)
        }
        XCTAssertTrue(processor.seen.isEmpty, "only a terminal pass emits a stop")
    }

    func testDuplicatePassCallbacksSubmitOnce() async {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let coordinator = ChallengeStopCoordinator(
            alarmID: AlarmID(alarmIDs.next()), processor: processor)
        _ = await coordinator.walkChallengeReached(.passed)
        _ = await coordinator.walkChallengeReached(.passed)
        _ = await coordinator.accessibleAlternativePassed()
        XCTAssertEqual(processor.seen.count, 1, "duplicate pass callbacks are idempotent")
    }

    func testAccessibleFallbackSubmitsStop() async {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let id = AlarmID(alarmIDs.next())
        let coordinator = ChallengeStopCoordinator(alarmID: id, processor: processor)
        _ = await coordinator.accessibleAlternativePassed()
        XCTAssertEqual(processor.seen, [.markChallengePassed(id)])
    }

    func testConcurrentPassesSubmitStopOnce() async {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let coordinator = ChallengeStopCoordinator(
            alarmID: AlarmID(alarmIDs.next()), processor: processor)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask { _ = await coordinator.walkChallengeReached(.passed) }
            }
        }
        XCTAssertEqual(processor.seen.count, 1, "racing passes emit exactly one stop")
    }
}
