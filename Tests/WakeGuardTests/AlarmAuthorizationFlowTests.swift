import XCTest

@testable import WakeGuard

/// WG-025: the AlarmKit authorization flow. Verifies the explanation precedes the
/// system prompt, each authorization state maps to a useful/recoverable step,
/// an interrupted request is kept-safe (never an assumed denial, #10), the Settings
/// deep link fires only where appropriate, and the flow never mutates alarms.
final class AlarmAuthorizationFlowTests: XCTestCase {

    private struct Fixture {
        let coordinator: AlarmAuthorizationCoordinator
        let adapter: FakeAlarmManagerAdapter
        let opener: FakeSettingsOpener
    }

    private func makeFixture(auth: AlarmAuthorizationState, openResult: Bool = true) -> Fixture {
        let adapter = FakeAlarmManagerAdapter(authorization: auth)
        let opener = FakeSettingsOpener(openResult: openResult)
        return Fixture(
            coordinator: AlarmAuthorizationCoordinator(adapter: adapter, settingsOpener: opener),
            adapter: adapter, opener: opener)
    }

    func testNotDeterminedShowsExplanationWithoutPrompting() async {
        let fixture = makeFixture(auth: .notDetermined)
        let step = await fixture.coordinator.currentStep()
        XCTAssertEqual(step, .explainThenRequest)
        XCTAssertEqual(
            fixture.adapter.requestAuthorizationCallCount, 0,
            "reading the step must not trigger the system prompt")
    }

    func testRequestAfterExplanationMapsAuthorized() async {
        let fixture = makeFixture(auth: .authorized)
        let step = await fixture.coordinator.requestAfterExplanation()
        XCTAssertEqual(step, .authorized)
        XCTAssertEqual(fixture.adapter.requestAuthorizationCallCount, 1)
    }

    func testRequestAfterExplanationMapsDenied() async {
        let fixture = makeFixture(auth: .denied)
        let step = await fixture.coordinator.requestAfterExplanation()
        XCTAssertEqual(step, .deniedOpenSettings)
        XCTAssertEqual(fixture.adapter.requestAuthorizationCallCount, 1)
    }

    func testRestrictedRoutesToFallback() async {
        let fixture = makeFixture(auth: .restricted)
        let step = await fixture.coordinator.currentStep()
        XCTAssertEqual(step, .restrictedUseFallback)
    }

    func testAuthorizedProceeds() async {
        let fixture = makeFixture(auth: .authorized)
        let step = await fixture.coordinator.currentStep()
        XCTAssertEqual(step, .authorized)
    }

    func testInterruptedRequestIsKeptSafeNotDenied() async {
        let fixture = makeFixture(auth: .notDetermined)
        fixture.adapter.inject(.unavailable, on: .requestAuthorization)
        let step = await fixture.coordinator.requestAfterExplanation()
        XCTAssertEqual(
            step, .unknownKeepSafe, "a thrown request is unknown, never an assumed denial (#10)")
    }

    func testStillNotDeterminedAfterRequestIsKeptSafe() async {
        // The request returned without error but the state is still not determined
        // (e.g. the prompt was dismissed) — keep-safe, not an assumed denial.
        let fixture = makeFixture(auth: .notDetermined)
        let step = await fixture.coordinator.requestAfterExplanation()
        XCTAssertEqual(step, .unknownKeepSafe)
        XCTAssertEqual(fixture.adapter.requestAuthorizationCallCount, 1)
    }

    func testOpenSettingsOnlyWhenDenied() async {
        let denied = makeFixture(auth: .denied)
        let openedDenied = await denied.coordinator.openSettingsIfAppropriate()
        XCTAssertTrue(openedDenied)
        XCTAssertEqual(denied.opener.openCount, 1)

        let restricted = makeFixture(auth: .restricted)
        let openedRestricted = await restricted.coordinator.openSettingsIfAppropriate()
        XCTAssertFalse(openedRestricted, "a Settings link cannot fix a restriction")
        XCTAssertEqual(restricted.opener.openCount, 0)

        let authorized = makeFixture(auth: .authorized)
        let openedAuthorized = await authorized.coordinator.openSettingsIfAppropriate()
        XCTAssertFalse(openedAuthorized)
        XCTAssertEqual(authorized.opener.openCount, 0)
    }

    func testFlowNeverMutatesAlarms() async {
        let fixture = makeFixture(auth: .denied)
        _ = await fixture.coordinator.currentStep()
        _ = await fixture.coordinator.requestAfterExplanation()
        _ = await fixture.coordinator.openSettingsIfAppropriate()

        // The authorization flow has no alarm-mutating capability — a denial preserves
        // every scheduled alarm (#10).
        XCTAssertTrue(fixture.adapter.scheduledRequests.isEmpty)
        XCTAssertTrue(fixture.adapter.cancelledAlarmIDs.isEmpty)
        XCTAssertTrue(fixture.adapter.snoozeCalls.isEmpty)
        XCTAssertTrue(fixture.adapter.currentlyScheduled.isEmpty)
    }
}
