import XCTest

@testable import WakeGuard

/// WG-024: the AlarmKit adapter port and its fake. Exercises schedule / cancel /
/// snooze / query / authorization on `FakeAlarmManagerAdapter`, and that the fake
/// can inject definite failures and — critically — `.uncertain` outcomes that leave
/// the system state for reconciliation (#10).
final class AlarmManagerAdapterTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 24)

    private func makeRequest(
        fireTime: Date, title: String = "wake", isCritical: Bool = false
    ) -> AlarmScheduleRequest {
        AlarmScheduleRequest(
            alarmID: AlarmID(ids.next()), fireTime: fireTime, title: title, isCritical: isCritical)
    }

    private func assertThrows(
        _ expected: AlarmManagerError, _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected) to be thrown")
        } catch let error as AlarmManagerError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testScheduleAddsToSystemAndRecordsRequest() async throws {
        let adapter = FakeAlarmManagerAdapter()
        let request = makeRequest(fireTime: Date(timeIntervalSince1970: 100), isCritical: true)
        try await adapter.schedule(request)

        XCTAssertEqual(adapter.scheduledRequests, [request])
        let scheduled = try await adapter.scheduledAlarms()
        XCTAssertEqual(
            scheduled,
            [
                ScheduledAlarmSnapshot(
                    alarmID: request.alarmID, fireTime: request.fireTime, isCritical: true)
            ])
    }

    func testCancelRemovesFromSystem() async throws {
        let adapter = FakeAlarmManagerAdapter()
        let request = makeRequest(fireTime: Date(timeIntervalSince1970: 100))
        try await adapter.schedule(request)
        try await adapter.cancel(alarmID: request.alarmID)

        XCTAssertEqual(adapter.cancelledAlarmIDs, [request.alarmID])
        let scheduled = try await adapter.scheduledAlarms()
        XCTAssertTrue(scheduled.isEmpty)

        // Cancelling an unknown id is a no-op, not an error.
        try await adapter.cancel(alarmID: AlarmID(ids.next()))
    }

    func testSnoozeReschedulesFireTime() async throws {
        let adapter = FakeAlarmManagerAdapter()
        let request = makeRequest(fireTime: Date(timeIntervalSince1970: 100))
        try await adapter.schedule(request)
        let until = Date(timeIntervalSince1970: 700)
        try await adapter.snooze(alarmID: request.alarmID, until: until)

        XCTAssertEqual(
            adapter.snoozeCalls,
            [FakeAlarmManagerAdapter.SnoozeCall(alarmID: request.alarmID, until: until)])
        let scheduled = try await adapter.scheduledAlarms()
        XCTAssertEqual(scheduled.map(\.fireTime), [until])
    }

    func testScheduleIsIdempotentOnAlarmID() async throws {
        let adapter = FakeAlarmManagerAdapter()
        let alarmID = AlarmID(ids.next())
        try await adapter.schedule(
            AlarmScheduleRequest(
                alarmID: alarmID, fireTime: Date(timeIntervalSince1970: 100), title: "v1",
                isCritical: false))
        try await adapter.schedule(
            AlarmScheduleRequest(
                alarmID: alarmID, fireTime: Date(timeIntervalSince1970: 200), title: "v2",
                isCritical: false))

        let scheduled = try await adapter.scheduledAlarms()
        XCTAssertEqual(scheduled.count, 1, "rescheduling replaces, not duplicates")
        XCTAssertEqual(scheduled.first?.fireTime, Date(timeIntervalSince1970: 200))
    }

    func testAuthorizationStateAndRequest() async throws {
        let adapter = FakeAlarmManagerAdapter(authorization: .notDetermined)
        let initial = await adapter.authorizationState()
        XCTAssertEqual(initial, .notDetermined)

        adapter.setAuthorization(.authorized)
        let requested = try await adapter.requestAuthorization()
        XCTAssertEqual(requested, .authorized)

        adapter.setAuthorization(.denied)
        let denied = await adapter.authorizationState()
        XCTAssertEqual(denied, .denied)
    }

    func testInjectedFailureIsThrownAndNotApplied() async throws {
        let adapter = FakeAlarmManagerAdapter()
        adapter.inject(.failed(reason: "system busy"), on: .schedule)
        let request = makeRequest(fireTime: Date(timeIntervalSince1970: 100))

        await assertThrows(.failed(reason: "system busy")) {
            try await adapter.schedule(request)
        }
        // A failed schedule did not apply — nothing is scheduled or recorded.
        let scheduled = try await adapter.scheduledAlarms()
        XCTAssertTrue(scheduled.isEmpty)
        XCTAssertTrue(adapter.scheduledRequests.isEmpty)

        // Clearing the injection lets the next call succeed.
        adapter.inject(nil, on: .schedule)
        try await adapter.schedule(request)
        let after = try await adapter.scheduledAlarms()
        XCTAssertEqual(after.count, 1)
    }

    func testInjectedUncertainCancelLeavesAlarmForReconciliation() async throws {
        let adapter = FakeAlarmManagerAdapter()
        let request = makeRequest(fireTime: Date(timeIntervalSince1970: 100))
        try await adapter.schedule(request)

        adapter.inject(.uncertain, on: .cancel)
        await assertThrows(.uncertain) {
            try await adapter.cancel(alarmID: request.alarmID)
        }
        // #10: an uncertain outcome must not be assumed — the alarm is still present,
        // so the caller reconciles (query) rather than assuming it was cancelled.
        let scheduled = try await adapter.scheduledAlarms()
        XCTAssertEqual(scheduled.map(\.alarmID), [request.alarmID])
    }

    func testInjectedErrorsArePerOperation() async throws {
        let adapter = FakeAlarmManagerAdapter()
        adapter.inject(.unavailable, on: .query)
        let request = makeRequest(fireTime: Date(timeIntervalSince1970: 100))

        // schedule still works; only the query throws.
        try await adapter.schedule(request)
        await assertThrows(.unavailable) {
            _ = try await adapter.scheduledAlarms()
        }
    }

    func testSeedScheduledSimulatesDivergence() async throws {
        let adapter = FakeAlarmManagerAdapter()
        let ghostID = AlarmID(ids.next())
        adapter.setScheduled([
            ScheduledAlarmSnapshot(
                alarmID: ghostID, fireTime: Date(timeIntervalSince1970: 500), isCritical: false)
        ])

        // The system holds an alarm the app never scheduled — a divergence WG-029
        // reconciliation must detect.
        let scheduled = try await adapter.scheduledAlarms()
        XCTAssertEqual(scheduled.map(\.alarmID), [ghostID])
        XCTAssertTrue(adapter.scheduledRequests.isEmpty, "the app did not schedule it")
    }

    func testNotAuthorizedInjectionOnSchedule() async {
        let adapter = FakeAlarmManagerAdapter(authorization: .denied)
        adapter.inject(.notAuthorized, on: .schedule)
        let request = makeRequest(fireTime: Date(timeIntervalSince1970: 100))
        await assertThrows(.notAuthorized) {
            try await adapter.schedule(request)
        }
    }

    func testRestrictedAuthorizationStateIsRepresented() async throws {
        let adapter = FakeAlarmManagerAdapter(authorization: .restricted)
        let state = await adapter.authorizationState()
        XCTAssertEqual(state, .restricted)
        let requested = try await adapter.requestAuthorization()
        XCTAssertEqual(requested, .restricted, "restricted is distinct from denied")
    }

    func testUncertainScheduleMayHaveApplied() async throws {
        let adapter = FakeAlarmManagerAdapter()
        let request = makeRequest(fireTime: Date(timeIntervalSince1970: 100), isCritical: true)

        // The call reports uncertain, but the operation may in fact have applied
        // system-side (#10). Model that: the throw, then a system that *does* hold the
        // alarm — so a caller must reconcile (query), never assume it failed and drop
        // the alarm (which would orphan a real system alarm).
        adapter.inject(.uncertain, on: .schedule)
        await assertThrows(.uncertain) {
            try await adapter.schedule(request)
        }
        adapter.setScheduled([
            ScheduledAlarmSnapshot(
                alarmID: request.alarmID, fireTime: request.fireTime, isCritical: true)
        ])
        let scheduled = try await adapter.scheduledAlarms()
        XCTAssertEqual(
            scheduled.map(\.alarmID), [request.alarmID],
            "an uncertain schedule that actually applied is discoverable by query")
    }

    func testCallLogsAreDistinctFromTheIdempotentSystemSet() async throws {
        let adapter = FakeAlarmManagerAdapter()
        let alarmID = AlarmID(ids.next())
        try await adapter.schedule(
            AlarmScheduleRequest(
                alarmID: alarmID, fireTime: Date(timeIntervalSince1970: 100), title: "v1",
                isCritical: false))
        try await adapter.schedule(
            AlarmScheduleRequest(
                alarmID: alarmID, fireTime: Date(timeIntervalSince1970: 200), title: "v2",
                isCritical: false))

        // The call log records both invocations; the system set stays idempotent (one).
        XCTAssertEqual(adapter.scheduledRequests.map(\.title), ["v1", "v2"])
        XCTAssertEqual(adapter.currentlyScheduled.count, 1)
    }
}
