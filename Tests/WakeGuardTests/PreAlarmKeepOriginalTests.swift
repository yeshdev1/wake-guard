import XCTest

@testable import WakeGuard

/// WG-084: the keep-original pre-alarm action. Verifies that tapping "Keep alarm" performs **no
/// schedule mutation** (the alarm stays exactly as scheduled, #7), that it records an
/// **acknowledgement** audit without changing the alarm (#46-style, old/new nil), that it is
/// **stale-safe** (a missing / deleted alarm is a safe no-op), and — through the real policy engine —
/// that keep is the safe default that is **never gated by confirmation**, even for a critical alarm.
final class PreAlarmKeepOriginalTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 84)

    private struct Fixture {
        let processor: AlarmCommandProcessor
        let alarms: CoreDataAlarmRepository
        let audit: CoreDataAuditRepository
        let adapter: FakeAlarmManagerAdapter
    }

    private func makeFixture(now: Date = Date(timeIntervalSince1970: 1_000_000)) throws -> Fixture {
        let controller = try PersistenceController(inMemory: true)
        let adapter = FakeAlarmManagerAdapter()
        let alarms = CoreDataAlarmRepository(controller)
        let audit = CoreDataAuditRepository(controller)
        let clock = TestClock(now: now)
        let processor = AlarmCommandProcessor(
            policy: DefaultAlarmPolicyEngine(
                alarms: alarms, clock: clock, deviceTimeZone: { .gmt }),
            alarms: alarms, audit: audit, outbox: CoreDataOutboxRepository(controller),
            alarmManager: adapter, clock: clock, ids: DeterministicIDGenerator(seed: 27),
            deviceTimeZone: { .gmt })
        return Fixture(processor: processor, alarms: alarms, audit: audit, adapter: adapter)
    }

    private func makeAlarm(criticality: Criticality = .standard) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule, criticality: criticality,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    // MARK: - No mutation + acknowledgement audit

    func testKeepDoesNotMutateAndRecordsAcknowledgement() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        let scheduledBefore = fixture.adapter.scheduledRequests.count

        let outcome = await fixture.processor.process(
            .keepOriginal(alarm.id), from: .notificationAction, by: .user)

        XCTAssertEqual(outcome, .noOp)
        // No schedule mutation: the alarm is byte-identical and no new adapter call was made (#7).
        let reloaded = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(reloaded, alarm, "keep changes nothing about the alarm")
        XCTAssertEqual(
            fixture.adapter.scheduledRequests.count, scheduledBefore, "no re-schedule from keep")
        XCTAssertTrue(fixture.adapter.cancelledAlarmIDs.isEmpty, "keep cancels nothing")
        XCTAssertTrue(fixture.adapter.stoppedRingIDs.isEmpty, "keep stops no ring")
        // The acknowledgement is audited without a state change.
        let last = try await fixture.audit.events(forAlarm: alarm.id).last
        XCTAssertEqual(last?.command, .keepOriginal(alarm.id))
        XCTAssertEqual(last?.outcome, .noOp)
        XCTAssertNil(last?.oldStateHash, "no prior state changed")
        XCTAssertNil(last?.newStateHash, "no new state")
    }

    // MARK: - Stale-safe

    func testKeepForMissingAlarmIsStaleSafeNoOp() async throws {
        let fixture = try makeFixture()
        let missing = AlarmID(ids.next())

        let outcome = await fixture.processor.process(
            .keepOriginal(missing), from: .notificationAction, by: .user)

        XCTAssertEqual(outcome, .noOp, "keep for an alarm that never existed is a safe no-op")
        XCTAssertTrue(fixture.adapter.scheduledRequests.isEmpty)
        XCTAssertTrue(fixture.adapter.cancelledAlarmIDs.isEmpty)
        XCTAssertTrue(fixture.adapter.stoppedRingIDs.isEmpty)
        let last = try await fixture.audit.events(forAlarm: missing).last
        XCTAssertEqual(
            last?.command, .keepOriginal(missing), "the acknowledgement is still recorded")
        XCTAssertEqual(last?.outcome, .noOp)
    }

    func testKeepAfterDeletionIsStaleSafe() async throws {
        let fixture = try makeFixture()
        let alarm = try makeAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        _ = await fixture.processor.process(.delete(alarm.id), from: .userInterface, by: .user)

        let outcome = await fixture.processor.process(
            .keepOriginal(alarm.id), from: .notificationAction, by: .user)

        XCTAssertEqual(outcome, .noOp, "keep on an already-deleted alarm is a safe no-op")
        let last = try await fixture.audit.events(forAlarm: alarm.id).last
        XCTAssertEqual(last?.command, .keepOriginal(alarm.id))
        XCTAssertEqual(last?.outcome, .noOp)
    }

    // MARK: - Never gated (the safe #7 default), even for a critical alarm

    func testKeepIsAuthorizedForCriticalAlarmWithoutConfirmation() async throws {
        let controller = try PersistenceController(inMemory: true)
        let alarms = CoreDataAlarmRepository(controller)
        let engine = DefaultAlarmPolicyEngine(
            alarms: alarms, clock: TestClock(now: Date(timeIntervalSince1970: 1_000_000)),
            deviceTimeZone: { .gmt })
        let critical = try makeAlarm(criticality: .critical)
        try await alarms.save(critical)

        let decision = await engine.authorize(
            .keepOriginal(critical.id), from: .notificationAction, userConfirmed: false)

        XCTAssertEqual(
            decision, .authorized,
            "keep is the safe default — never gated, even for a critical alarm unconfirmed (#6/#7)")
    }

    func testKeepThroughProcessorForCriticalNeverNeedsConfirmation() async throws {
        let fixture = try makeFixture()
        let critical = try makeAlarm(criticality: .critical)
        _ = await fixture.processor.process(.create(critical), from: .userInterface, by: .user)

        let outcome = await fixture.processor.process(
            .keepOriginal(critical.id), from: .notificationAction, by: .user, userConfirmed: false)

        XCTAssertEqual(
            outcome, .noOp, "a critical alarm's keep is a no-op, never .needsConfirmation")
    }

    func testKeepFromAgentProposalSourceIsStillANoOp() async throws {
        // Keep from ANY source can only ever no-op — an AI-sourced keep mutates nothing (#4/#8).
        let fixture = try makeFixture()
        let critical = try makeAlarm(criticality: .critical)
        _ = await fixture.processor.process(.create(critical), from: .userInterface, by: .user)
        let scheduledBefore = fixture.adapter.scheduledRequests.count

        let outcome = await fixture.processor.process(
            .keepOriginal(critical.id), from: .agentProposal, by: .approvedAgentProposal)

        XCTAssertEqual(outcome, .noOp)
        XCTAssertEqual(
            fixture.adapter.scheduledRequests.count, scheduledBefore,
            "an agent keep mutates nothing")
        XCTAssertTrue(fixture.adapter.cancelledAlarmIDs.isEmpty)
        XCTAssertTrue(fixture.adapter.stoppedRingIDs.isEmpty)
        let reloaded = try await fixture.alarms.alarm(id: critical.id)
        XCTAssertEqual(reloaded, critical)
    }
}
