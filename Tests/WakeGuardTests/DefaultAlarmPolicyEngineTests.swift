import XCTest

@testable import WakeGuard

/// WG-028: the deterministic policy engine. Verifies that additive commands are
/// authorized, that cancelling/weakening a critical (or imminent) alarm requires
/// explicit confirmation (#6), that an AI proposal can never suppress a critical alarm
/// (#4), and that every denial carries a user-displayable reason.
final class DefaultAlarmPolicyEngineTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 28)

    /// Weekly all-days 07:00 UTC. With `now` at 06:00 the next fire is ~1h away (not
    /// imminent); at 06:58 it is 2 min away (imminent, within the 300s window).
    private func makeAlarm(criticality: Criticality) throws -> Alarm {
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

    private func iso(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func makeEngine(now: Date) throws -> (DefaultAlarmPolicyEngine, CoreDataAlarmRepository)
    {
        let alarms = CoreDataAlarmRepository(try PersistenceController(inMemory: true))
        let engine = DefaultAlarmPolicyEngine(
            alarms: alarms, clock: TestClock(now: now), deviceTimeZone: { .gmt })
        return (engine, alarms)
    }

    func testAdditiveCommandsAreAuthorizedEvenForCriticalFromAgent() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:00:00Z"))
        let alarm = try makeAlarm(criticality: .critical)
        try await alarms.save(alarm)

        let create = await engine.authorize(
            .create(alarm), from: .agentProposal, userConfirmed: false)
        XCTAssertEqual(create, .authorized)
        let enable = await engine.authorize(
            .enable(alarm.id), from: .agentProposal, userConfirmed: false)
        XCTAssertEqual(enable, .authorized)
    }

    func testCancellingCriticalAlarmRequiresConfirmation() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:00:00Z"))
        let alarm = try makeAlarm(criticality: .critical)
        try await alarms.save(alarm)

        let unconfirmed = await engine.authorize(
            .disable(alarm.id), from: .userInterface, userConfirmed: false)
        guard case .needsConfirmation(let reason) = unconfirmed else {
            return XCTFail("cancelling a critical alarm must require confirmation (#6)")
        }
        XCTAssertFalse(reason.isEmpty, "the deny reason must be user-displayable")

        let confirmed = await engine.authorize(
            .disable(alarm.id), from: .userInterface, userConfirmed: true)
        XCTAssertEqual(confirmed, .authorized)
    }

    func testAgentCannotSuppressCriticalAlarmEvenConfirmed() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:00:00Z"))
        let alarm = try makeAlarm(criticality: .critical)
        try await alarms.save(alarm)

        let decision = await engine.authorize(
            .disable(alarm.id), from: .agentProposal, userConfirmed: true)
        guard case .rejected = decision else {
            return XCTFail("an AI proposal must never suppress a critical alarm (#4)")
        }
    }

    func testImminentNonCriticalCancelRequiresConfirmation() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:58:00Z"))
        let alarm = try makeAlarm(criticality: .standard)
        try await alarms.save(alarm)

        let unconfirmed = await engine.authorize(
            .disable(alarm.id), from: .userInterface, userConfirmed: false)
        guard case .needsConfirmation = unconfirmed else {
            return XCTFail("an imminent alarm cancel must require confirmation")
        }
        let confirmed = await engine.authorize(
            .disable(alarm.id), from: .userInterface, userConfirmed: true)
        XCTAssertEqual(confirmed, .authorized)
    }

    func testNonImminentNonCriticalCancelIsAuthorized() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:00:00Z"))
        let alarm = try makeAlarm(criticality: .standard)
        try await alarms.save(alarm)

        let decision = await engine.authorize(
            .disable(alarm.id), from: .userInterface, userConfirmed: false)
        XCTAssertEqual(decision, .authorized)
    }

    func testUpdateGatesOnlyCriticalAlarms() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:00:00Z"))
        let standard = try makeAlarm(criticality: .standard)
        try await alarms.save(standard)
        let updateStandard = await engine.authorize(
            .update(standard), from: .userInterface, userConfirmed: false)
        XCTAssertEqual(updateStandard, .authorized)

        let critical = try makeAlarm(criticality: .critical)
        try await alarms.save(critical)
        let updateCritical = await engine.authorize(
            .update(critical), from: .userInterface, userConfirmed: false)
        guard case .needsConfirmation = updateCritical else {
            return XCTFail("changing a critical alarm must require confirmation")
        }
    }

    func testCancellingUnknownAlarmIsAuthorized() async throws {
        let (engine, _) = try makeEngine(now: try iso("2026-08-17T06:00:00Z"))
        let decision = await engine.authorize(
            .disable(AlarmID(ids.next())), from: .userInterface, userConfirmed: false)
        XCTAssertEqual(decision, .authorized, "no alarm exists to protect")
    }

    /// A *thrown* read error is not "no alarm" — the engine cannot tell whether this is
    /// a critical alarm, so it must fail **closed** (reject), never fail open. Otherwise
    /// a transient storage fault would authorize an unconfirmed critical suppression
    /// from the user *or* the AI (#6, #4).
    func testStorageReadErrorFailsClosedForUserAndAgent() async throws {
        let engine = DefaultAlarmPolicyEngine(
            alarms: FailingAlarmRepository(),
            clock: TestClock(now: try iso("2026-08-17T06:00:00Z")), deviceTimeZone: { .gmt })
        let id = AlarmID(ids.next())

        let user = await engine.authorize(
            .disable(id), from: .userInterface, userConfirmed: false)
        guard case .rejected(let reason) = user else {
            return XCTFail("a storage read error must fail closed, not authorize (#6)")
        }
        XCTAssertFalse(reason.isEmpty, "the deny reason must be user-displayable")

        let agent = await engine.authorize(
            .disable(id), from: .agentProposal, userConfirmed: false)
        guard case .rejected = agent else {
            return XCTFail("a storage read error must fail closed for an agent too (#4)")
        }
    }

    /// A disabled alarm has no upcoming fire, so it is never "imminent": cancelling one
    /// inside the wall-clock window must be authorized (and must not be mislabelled
    /// "about to go off").
    func testDisabledAlarmInsideWindowIsAuthorized() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:58:00Z"))
        var alarm = try makeAlarm(criticality: .standard)
        alarm.isEnabled = false
        try await alarms.save(alarm)

        let decision = await engine.authorize(
            .disable(alarm.id), from: .userInterface, userConfirmed: false)
        XCTAssertEqual(decision, .authorized, "a disabled alarm has no imminent fire to protect")
    }

    /// #6 covers "delayed": snoozing is a delay, so an AI proposal must never snooze a
    /// critical alarm — even flagged confirmed.
    func testSnoozingCriticalAlarmFromAgentIsRejected() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:00:00Z"))
        let alarm = try makeAlarm(criticality: .critical)
        try await alarms.save(alarm)

        let decision = await engine.authorize(
            .snooze(alarm.id), from: .agentProposal, userConfirmed: true)
        guard case .rejected = decision else {
            return XCTFail("an AI proposal must never delay (snooze) a critical alarm (#6/#4)")
        }
    }

    /// Occurrence-level destructive commands are gated like any other: cancelling one
    /// occurrence of a critical alarm needs confirmation.
    func testCancellingOccurrenceOfCriticalAlarmRequiresConfirmation() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:00:00Z"))
        let alarm = try makeAlarm(criticality: .critical)
        try await alarms.save(alarm)
        let fireTime = try iso("2026-08-24T07:00:00Z")

        let unconfirmed = await engine.authorize(
            .cancelOccurrence(alarm.id, fireTime: fireTime), from: .userInterface,
            userConfirmed: false)
        guard case .needsConfirmation = unconfirmed else {
            return XCTFail("cancelling an occurrence of a critical alarm needs confirmation (#6)")
        }
        let confirmed = await engine.authorize(
            .cancelOccurrence(alarm.id, fireTime: fireTime), from: .userInterface,
            userConfirmed: true)
        XCTAssertEqual(confirmed, .authorized)
    }

    /// The imminent window is inclusive (`<=`): a fire exactly 300s away is imminent; one
    /// second beyond it is not. Pins the boundary so a future `<`/`<=` slip is caught.
    func testImminentWindowBoundaryIsInclusive() async throws {
        let (atEdge, atEdgeAlarms) = try makeEngine(now: try iso("2026-08-17T06:55:00Z"))
        let edgeAlarm = try makeAlarm(criticality: .standard)
        try await atEdgeAlarms.save(edgeAlarm)
        let edge = await atEdge.authorize(
            .disable(edgeAlarm.id), from: .userInterface, userConfirmed: false)
        guard case .needsConfirmation = edge else {
            return XCTFail("exactly 300s to fire is within the inclusive imminent window")
        }

        let (beyond, beyondAlarms) = try makeEngine(now: try iso("2026-08-17T06:54:59Z"))
        let beyondAlarm = try makeAlarm(criticality: .standard)
        try await beyondAlarms.save(beyondAlarm)
        let outside = await beyond.authorize(
            .disable(beyondAlarm.id), from: .userInterface, userConfirmed: false)
        XCTAssertEqual(outside, .authorized, "301s to fire is outside the 300s window")
    }

    func testDeletingCriticalAlarmRequiresConfirmation() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:00:00Z"))
        let alarm = try makeAlarm(criticality: .critical)
        try await alarms.save(alarm)

        let unconfirmed = await engine.authorize(
            .delete(alarm.id), from: .userInterface, userConfirmed: false)
        guard case .needsConfirmation = unconfirmed else {
            return XCTFail("deleting a critical alarm needs confirmation (#6)")
        }
        let confirmed = await engine.authorize(
            .delete(alarm.id), from: .userInterface, userConfirmed: true)
        XCTAssertEqual(confirmed, .authorized)
    }

    func testDeletingStandardNonImminentAlarmIsAuthorized() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:00:00Z"))
        let alarm = try makeAlarm(criticality: .standard)  // fires 07:00; now 06:00 → not imminent
        try await alarms.save(alarm)

        let decision = await engine.authorize(
            .delete(alarm.id), from: .userInterface, userConfirmed: false)
        XCTAssertEqual(decision, .authorized, "a routine delete doesn't require confirmation")
    }
}

/// A repository whose reads always throw — proves the policy engine fails *closed*
/// (rejects) when it cannot load the alarm, rather than fail open (#6, #4).
private struct FailingAlarmRepository: AlarmRepository {
    func save(_ alarm: Alarm) async throws { throw AlarmRepositoryError.storageUnavailable }
    func alarm(id: AlarmID) async throws -> Alarm? { throw AlarmRepositoryError.storageUnavailable }
    func allAlarms() async throws -> [Alarm] { throw AlarmRepositoryError.storageUnavailable }
    func deleteAlarm(id: AlarmID) async throws { throw AlarmRepositoryError.storageUnavailable }
}
