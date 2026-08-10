import XCTest

@testable import WakeGuard

/// WG-018: the composed dependency graph. Verifies the in-memory (test/preview)
/// graph wires every port to one shared store, that the clock and id generator are
/// injectable (deterministic in tests), that two graphs are isolated (no shared
/// locator), and that the production graph uses the live clock/id generator.
final class AppEnvironmentTests: XCTestCase {

    private func makeAlarm(id: AlarmID) throws -> Alarm {
        let schedule = ScheduleRule.oneTime(
            OneTimeSchedule(
                date: try CalendarDate(year: 2026, month: 8, day: 15),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: id, label: "wake", schedule: schedule,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    private func makeAudit(alarmID: AlarmID, ids: DeterministicIDGenerator) -> AuditEvent {
        AuditEvent(
            id: AuditEventID(ids.next()), actor: .user, command: .snooze(alarmID),
            oldStateHash: nil, newStateHash: "h", timestamp: Date(timeIntervalSince1970: 1),
            source: .userInterface, outcome: .succeeded,
            correlationID: CorrelationID(ids.next()), userVisibleReason: "snoozed")
    }

    private func makeOutbox(alarmID: AlarmID, ids: DeterministicIDGenerator) -> OutboxEntry {
        OutboxEntry(
            id: OutboxEntryID(ids.next()), command: .disable(alarmID),
            idempotencyKey: "key-\(alarmID.rawValue.uuidString)", status: .pending,
            createdAt: Date(timeIntervalSince1970: 2), attempts: 0, lastFailureReason: nil)
    }

    func testInMemoryGraphRoundTripsThroughEveryRepository() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let ids = DeterministicIDGenerator(seed: 18)
        let env = try AppEnvironment.inMemory(clock: clock, identifierGenerator: ids)

        // Alarm repository.
        let alarmID = AlarmID(ids.next())
        let alarm = try makeAlarm(id: alarmID)
        try await env.alarmRepository.save(alarm)
        let loadedAlarm = try await env.alarmRepository.alarm(id: alarmID)
        XCTAssertEqual(loadedAlarm, alarm)

        // Audit repository.
        let event = makeAudit(alarmID: alarmID, ids: ids)
        try await env.auditRepository.append(event)
        let history = try await env.auditRepository.events(forAlarm: alarmID)
        XCTAssertEqual(history.map(\.id), [event.id])

        // Outbox repository.
        let entry = makeOutbox(alarmID: alarmID, ids: ids)
        try await env.outboxRepository.enqueue(entry)
        let pending = try await env.outboxRepository.pendingEntries()
        XCTAssertEqual(pending.map(\.id), [entry.id])

        // Settings repository (round-trips a change).
        var settings = try await env.settingsRepository.settings()
        XCTAssertEqual(settings, .default)
        settings.preAlarmPromptEnabled = true
        try await env.settingsRepository.save(settings)
        let reloaded = try await env.settingsRepository.settings()
        XCTAssertEqual(reloaded, settings)
    }

    func testInMemoryGraphUsesInjectedClockAndIdentifierGenerator() throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 42))
        let ids = DeterministicIDGenerator(seed: 7)
        let env = try AppEnvironment.inMemory(clock: clock, identifierGenerator: ids)

        XCTAssertEqual(env.clock.now, Date(timeIntervalSince1970: 42))
        // The injected generator is what the graph uses — deterministic per seed.
        XCTAssertEqual(env.identifierGenerator.next(), DeterministicIDGenerator(seed: 7).next())
    }

    func testSeparateInMemoryGraphsAreIsolated() async throws {
        let ids = DeterministicIDGenerator(seed: 3)
        let envA = try AppEnvironment.inMemory()
        let envB = try AppEnvironment.inMemory()

        let alarm = try makeAlarm(id: AlarmID(ids.next()))
        try await envA.alarmRepository.save(alarm)

        let inA = try await envA.alarmRepository.allAlarms()
        let inB = try await envB.alarmRepository.allAlarms()
        XCTAssertEqual(inA.count, 1)
        XCTAssertTrue(
            inB.isEmpty, "each graph is an independent store — no shared or global state")
    }

    func testLiveAdaptersReadRealTimeAndProduceUniqueIds() {
        // The live adapters directly — no graph, no disk (`production()` writes a
        // real store, so it is exercised at app launch, not from a unit test).
        XCTAssertEqual(SystemClock().now.timeIntervalSinceNow, 0, accuracy: 5)
        let generator = SystemIdentifierGenerator()
        XCTAssertNotEqual(generator.next(), generator.next(), "live ids are unique")
    }

    func testGraphDefaultsToLiveAdapters() throws {
        // The container's default clock/id generator — what `production()` also uses —
        // are the live adapters. Asserted via the in-memory graph so no disk is
        // touched.
        let env = try AppEnvironment.inMemory()
        XCTAssertTrue(env.clock is SystemClock)
        XCTAssertTrue(env.identifierGenerator is SystemIdentifierGenerator)
    }

    func testInMemoryGraphDoesNotScheduleInSystem() throws {
        // The in-memory (test/preview) graph composes the interim deferred adapter, so it never claims
        // to place alarms in the system authority — the list shows the "won't ring here" banner.
        let env = try AppEnvironment.inMemory()
        XCTAssertFalse(env.schedulesAlarmsInSystem)
    }

    func testAuthorizationCoordinatorIsWiredAndReadsStateWithoutMutatingAlarms() async throws {
        // The coordinator is composed over the same adapter the processor uses; the deferred adapter
        // reports `.notDetermined`, so the step routes through the explanation first — and reading it
        // never creates or mutates an alarm (#10).
        let env = try AppEnvironment.inMemory()
        let step = await env.authorizationCoordinator.currentStep()
        XCTAssertEqual(step, .explainThenRequest)
        let alarms = try await env.alarmRepository.allAlarms()
        XCTAssertTrue(alarms.isEmpty, "reading authorization never creates or mutates an alarm")
    }

    func testInMemoryGraphComposesAPreAlarmResponderThatIgnoresACorruptPayload() async throws {
        // The graph wires the notification responder (over the no-op scheduler + the processor); a
        // corrupt payload is ignored — never mis-applied to an alarm (#7).
        let env = try AppEnvironment.inMemory()
        let effect = await env.preAlarmResponder.handle(
            actionIdentifier: "prealarm.action.turnOffToday", userInfo: [:],
            now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(effect, PreAlarmResponseEffect.none)
    }

    func testInMemoryGraphComposesAWorkingFeedbackStore() async throws {
        // WG-090 step 7: the graph composes the pre-alarm feedback store; feedback round-trips through
        // it (advisory + on-device; the store's own tests pin that it never touches an alarm).
        let env = try AppEnvironment.inMemory()
        await env.preAlarmFeedback.record(.helpful)
        let counts = await env.preAlarmFeedback.counts()
        XCTAssertEqual(counts.helpfulCount, 1, "feedback round-trips through the composed store")
    }

    func testAppEnvironmentIsSendable() {
        // Compile-time guard: the container is delivered through the SwiftUI
        // environment across isolation, so it must stay Sendable. If a future port
        // drops its Sendable constraint, this call fails to compile at the source.
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(AppEnvironment.self)
    }
}
