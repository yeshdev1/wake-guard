import Foundation
import XCTest

@testable import WakeGuard

/// WG-172 (review-demanded integration): the AgentOrchestrator handoff through the **real**
/// `AlarmCommandProcessor` + `DefaultAlarmPolicyEngine` + Core Data repositories. Proves the end-to-end
/// critical-alarm guarantee the fakes can't: an agent-proposed **destructive** change to a genuinely
/// critical alarm is **rejected by the engine — confirmed or not**, the alarm is not mutated, and the
/// audit records a rejected *AI* proposal (never a user action).
final class AgentOrchestratorIntegrationTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 99)

    private func makeCriticalAlarm() throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule,
            travelBehavior: .followLocal,
            criticality: .critical, createdAt: epoch, updatedAt: epoch, revision: 3)
    }

    private struct Fixture {
        let orchestrator: AgentOrchestrator
        let processor: AlarmCommandProcessor
        let alarms: CoreDataAlarmRepository
        let audit: CoreDataAuditRepository
    }

    private func makeFixture() throws -> Fixture {
        let controller = try PersistenceController(inMemory: true)
        let alarms = CoreDataAlarmRepository(controller)
        let audit = CoreDataAuditRepository(controller)
        let clock = TestClock(now: Date(timeIntervalSince1970: 0))
        let processor = AlarmCommandProcessor(
            policy: DefaultAlarmPolicyEngine(
                alarms: alarms, clock: clock, deviceTimeZone: { .gmt }),
            alarms: alarms, audit: audit, outbox: CoreDataOutboxRepository(controller),
            alarmManager: FakeAlarmManagerAdapter(), clock: clock,
            ids: DeterministicIDGenerator(seed: 27), deviceTimeZone: { .gmt })
        return Fixture(
            orchestrator: AgentOrchestrator(processor: processor), processor: processor,
            alarms: alarms, audit: audit)
    }

    func testConfirmedAgentProposalCannotChangeACriticalAlarm() async throws {
        let fixture = try makeFixture()
        let alarm = try makeCriticalAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        let afterCreate = try XCTUnwrap(stored)
        XCTAssertEqual(afterCreate.criticality, .critical)

        // A CONFIRMED agent proposal to delete the critical alarm — the engine must still reject it (#4).
        let result = await fixture.orchestrator.apply(
            .delete(alarm.id), mode: .askBeforeActing, targetIsCritical: true, userConfirmed: true)
        guard case .handed(.rejected) = result else {
            return XCTFail(
                "a confirmed agent delete of a critical alarm must be rejected: \(result)")
        }

        // The critical alarm is unchanged by the rejected agent delete.
        let afterDelete = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(afterDelete, afterCreate)

        // The rejection is audited as an AI proposal, never a user action.
        let events = try await fixture.audit.events(forAlarm: alarm.id)
        let rejection = try XCTUnwrap(events.first { $0.outcome == .rejected })
        XCTAssertEqual(rejection.actor, .approvedAgentProposal)
    }

    func testUnconfirmedAgentProposalNeverEvenSubmits() async throws {
        let fixture = try makeFixture()
        let alarm = try makeCriticalAlarm()
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        let stored = try await fixture.alarms.alarm(id: alarm.id)
        let afterCreate = try XCTUnwrap(stored)
        let auditBefore = try await fixture.audit.events(forAlarm: alarm.id).count

        let result = await fixture.orchestrator.apply(
            .delete(alarm.id), mode: .askBeforeActing, targetIsCritical: true, userConfirmed: false)
        XCTAssertEqual(result, .needsUserConfirmation)

        // Nothing was submitted: no new audit event, alarm unchanged.
        let auditAfter = try await fixture.audit.events(forAlarm: alarm.id).count
        XCTAssertEqual(auditAfter, auditBefore)
        let afterUnconfirmed = try await fixture.alarms.alarm(id: alarm.id)
        XCTAssertEqual(afterUnconfirmed, afterCreate)
    }
}
