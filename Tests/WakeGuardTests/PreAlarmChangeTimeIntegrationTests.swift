import XCTest

@testable import WakeGuard

/// WG-086 change-time — processor integration: the original alarm stays active until a save succeeds,
/// and an imminent / critical save is confirmation-gated (#6), never suppressing the ring.
final class PreAlarmChangeTimeIntegrationTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 86)

    private func iso(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func makeAlarm(
        criticality: Criticality = .standard, hour: Int = 7,
        travel: TravelBehavior = .followLocal
    ) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: hour, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule, travelBehavior: travel,
            criticality: criticality, createdAt: epoch, updatedAt: epoch, revision: 3)
    }

    // MARK: - Processor: original stays active until a save succeeds

    private struct Fixture {
        let processor: AlarmCommandProcessor
        let alarms: CoreDataAlarmRepository
        let audit: CoreDataAuditRepository
        let adapter: FakeAlarmManagerAdapter
    }

    private func reload(_ id: AlarmID, in fixture: Fixture) async throws -> Alarm {
        let loaded = try await fixture.alarms.alarm(id: id)
        return try XCTUnwrap(loaded)
    }

    private func makeFixture(now: Date) throws -> Fixture {
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

    func testBuildingAProposalTouchesNeitherRepoNorAdapter() async throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let fixture = try makeFixture(now: now)
        let alarm = try makeAlarm(hour: 7)
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        let scheduledBefore = fixture.adapter.scheduledRequests.count
        let auditBefore = try await fixture.audit.events(forAlarm: alarm.id).count

        // Merely open + preview + build-command. None of this goes through the processor.
        let proposal = ChangeTimeProposal(
            target: alarm, proposedTime: try TimeOfDay(hour: 9, minute: 0))
        _ = proposal.previewNextOccurrence(after: now, deviceTimeZone: .gmt)
        _ = proposal.command(now: now)

        let reloaded = try await reload(alarm.id, in: fixture)
        XCTAssertEqual(
            reloaded, alarm, "the stored alarm is unchanged while a proposal is open (#7)")
        XCTAssertEqual(
            fixture.adapter.scheduledRequests.count, scheduledBefore,
            "no re-schedule from a proposal")
        XCTAssertTrue(fixture.adapter.cancelledAlarmIDs.isEmpty, "a proposal cancels nothing")
        XCTAssertTrue(fixture.adapter.stoppedRingIDs.isEmpty, "a proposal stops no ring")
        let auditAfter = try await fixture.audit.events(forAlarm: alarm.id).count
        XCTAssertEqual(auditAfter, auditBefore, "opening a proposal records no audit event")
    }

    func testOriginalScheduleStaysArmedUntilSaveSucceeds() async throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let fixture = try makeFixture(now: now)
        let alarm = try makeAlarm(hour: 7)
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        // AlarmKit is armed for the ORIGINAL 07:00 occurrence.
        XCTAssertEqual(
            fixture.adapter.scheduledRequests.last?.fireTime, try iso("2026-08-17T07:00:00Z"))

        // The user reviews a proposal to move it to 09:00, then SAVES it (a normal .update).
        let proposal = ChangeTimeProposal(
            target: alarm, proposedTime: try TimeOfDay(hour: 9, minute: 0))
        let command = try XCTUnwrap(proposal.command(now: now))
        let outcome = await fixture.processor.process(command, from: .userInterface, by: .user)

        XCTAssertEqual(outcome, .applied)
        let reloaded = try await reload(alarm.id, in: fixture)
        XCTAssertEqual(
            reloaded.schedule.time, try TimeOfDay(hour: 9, minute: 0),
            "only after a successful save does the stored time change")
        XCTAssertEqual(
            fixture.adapter.scheduledRequests.last?.fireTime, try iso("2026-08-17T09:00:00Z"),
            "AlarmKit is re-armed to the new time only on save")
        XCTAssertGreaterThan(reloaded.revision, alarm.revision)
    }

    func testSaveWithFailedAlarmKitPlacementKeepsDesiredTimeDurableForReconcile() async throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let fixture = try makeFixture(now: now)
        let alarm = try makeAlarm(hour: 7)
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)
        // The system reschedule fails; the local save of a non-critical update still persists, so the
        // *desired* time changes locally (source of truth first, #10) and reconciliation re-arms
        // AlarmKit — the alarm is never lost. A failed *placement* is repaired, not silently dropped.
        fixture.adapter.inject(.failed(reason: "system busy"), on: .schedule)
        let proposal = ChangeTimeProposal(
            target: alarm, proposedTime: try TimeOfDay(hour: 9, minute: 0))
        let command = try XCTUnwrap(proposal.command(now: now))

        let outcome = await fixture.processor.process(command, from: .userInterface, by: .user)

        guard case .failed = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        // The local desired state advanced (source of truth first, #10); reconciliation will re-arm.
        let reloaded = try await reload(alarm.id, in: fixture)
        XCTAssertEqual(
            reloaded.schedule.time, try TimeOfDay(hour: 9, minute: 0),
            "the saved desired time is durable; a failed AlarmKit placement is repaired by reconcile"
        )
    }

    // MARK: - Imminent / critical race: save is confirmation-gated (#6), ring never suppressed

    func testSavingProposalForCriticalAlarmNeedsConfirmationAndMutatesNothing() async throws {
        let now = try iso("2026-08-17T06:00:00Z")
        let fixture = try makeFixture(now: now)
        let critical = try makeAlarm(criticality: .critical, hour: 7)
        _ = await fixture.processor.process(.create(critical), from: .userInterface, by: .user)
        let armedFireTime = fixture.adapter.scheduledRequests.last?.fireTime

        let proposal = ChangeTimeProposal(
            target: critical, proposedTime: try TimeOfDay(hour: 9, minute: 0))
        let command = try XCTUnwrap(proposal.command(now: now))
        let unconfirmed = await fixture.processor.process(
            command, from: .notificationAction, by: .user, userConfirmed: false)

        guard case .needsConfirmation = unconfirmed else {
            return XCTFail("saving a critical retime unconfirmed must need confirmation (#6)")
        }
        let unchanged = try await reload(critical.id, in: fixture)
        XCTAssertEqual(
            unchanged.schedule.time, try TimeOfDay(hour: 7, minute: 0),
            "no mutation without confirmation — the critical alarm keeps its original time")
        XCTAssertEqual(
            fixture.adapter.scheduledRequests.last?.fireTime, armedFireTime,
            "the critical alarm's original ring is NOT suppressed while unconfirmed")

        // Re-submitting with explicit confirmation applies the retime.
        let confirmed = await fixture.processor.process(
            command, from: .notificationAction, by: .user, userConfirmed: true)
        XCTAssertEqual(confirmed, .applied)
        let saved = try await reload(critical.id, in: fixture)
        XCTAssertEqual(
            saved.schedule.time, try TimeOfDay(hour: 9, minute: 0), "confirmed retime saved")
    }

    func testSavingProposalForImminentStandardAlarmApplies() async throws {
        // The alarm fires at 07:00; now is 06:58 (imminent). Editing a *standard* alarm is authorized
        // without confirmation (WG-028: only a critical update is imminence/#6-gated — see the critical
        // test). The proposal was inert until this save, so opening it never suppressed the original
        // ring; the save simply reschedules to the new time.
        let now = try iso("2026-08-17T06:58:00Z")
        let fixture = try makeFixture(now: now)
        let alarm = try makeAlarm(criticality: .standard, hour: 7)
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)

        let proposal = ChangeTimeProposal(
            target: alarm, proposedTime: try TimeOfDay(hour: 9, minute: 0))
        let command = try XCTUnwrap(proposal.command(now: now))
        let outcome = await fixture.processor.process(
            command, from: .notificationAction, by: .user, userConfirmed: false)

        XCTAssertEqual(
            outcome, .applied, "a standard alarm's retime is authorized without confirmation")
        let retimed = try await reload(alarm.id, in: fixture)
        XCTAssertEqual(
            retimed.schedule.time, try TimeOfDay(hour: 9, minute: 0),
            "saved to the new time (the imminent ring is rescheduled, not silently kept)")
    }

    func testSavingProposalForFarOffStandardAlarmAppliesWithoutConfirmation() async throws {
        // Not imminent (07:00 tomorrow relative to 06:00 today's window? it's ~1h — but standard,
        // non-critical, editing a standard alarm is authorized). Use a far-off now to be safe.
        let now = try iso("2026-08-17T00:00:00Z")
        let fixture = try makeFixture(now: now)
        let alarm = try makeAlarm(criticality: .standard, hour: 7)
        _ = await fixture.processor.process(.create(alarm), from: .userInterface, by: .user)

        let proposal = ChangeTimeProposal(
            target: alarm, proposedTime: try TimeOfDay(hour: 9, minute: 0))
        let command = try XCTUnwrap(proposal.command(now: now))
        let outcome = await fixture.processor.process(
            command, from: .notificationAction, by: .user, userConfirmed: false)

        XCTAssertEqual(
            outcome, .applied,
            "editing a far-off standard alarm is authorized without confirmation")
    }
}
