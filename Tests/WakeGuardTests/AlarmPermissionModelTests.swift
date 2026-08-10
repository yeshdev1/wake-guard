import XCTest

@testable import WakeGuard

/// Runs-on-a-phone step 2: the alarm-authorization UI model. Verifies it reflects each authorization
/// state, never prompts on a plain refresh, keeps an interrupted request **safe** (never an assumed
/// denial, #10), routes a denial to Settings, and — the safety pin — never mutates an alarm while
/// driving permission (the permission UI holds no alarm authority, #8/#10). `@MainActor` because the
/// model feeds SwiftUI.
@MainActor
final class AlarmPermissionModelTests: XCTestCase {

    private struct Fixture {
        let model: AlarmPermissionModel
        let adapter: FakeAlarmManagerAdapter
        let opener: FakeSettingsOpener
    }

    private func makeFixture(auth: AlarmAuthorizationState, openResult: Bool = true) -> Fixture {
        let adapter = FakeAlarmManagerAdapter(authorization: auth)
        let opener = FakeSettingsOpener(openResult: openResult)
        let coordinator = AlarmAuthorizationCoordinator(adapter: adapter, settingsOpener: opener)
        return Fixture(
            model: AlarmPermissionModel(coordinator: coordinator), adapter: adapter, opener: opener)
    }

    func testStepIsNilBeforeFirstRefresh() {
        let fixture = makeFixture(auth: .notDetermined)
        XCTAssertNil(fixture.model.step, "nothing is surfaced until authorization has been read")
    }

    func testRefreshNotDeterminedShowsExplainThenRequestWithoutPrompting() async {
        let fixture = makeFixture(auth: .notDetermined)
        await fixture.model.refresh()
        XCTAssertEqual(fixture.model.step, .explainThenRequest)
        XCTAssertEqual(
            fixture.adapter.requestAuthorizationCallCount, 0, "a refresh must never prompt")
    }

    func testRequestAfterExplanationAuthorizes() async {
        let fixture = makeFixture(auth: .authorized)
        await fixture.model.requestAfterExplanation()
        XCTAssertEqual(fixture.model.step, .authorized)
        XCTAssertEqual(fixture.adapter.requestAuthorizationCallCount, 1)
    }

    func testInterruptedRequestIsKeptSafeNotDenied() async {
        let fixture = makeFixture(auth: .notDetermined)
        fixture.adapter.inject(.unavailable, on: .requestAuthorization)
        await fixture.model.requestAfterExplanation()
        XCTAssertEqual(
            fixture.model.step, .unknownKeepSafe,
            "an interrupted request is never an assumed denial (#10)")
    }

    func testOpenSettingsForDeniedOpensAndReReadsState() async {
        let fixture = makeFixture(auth: .denied)
        await fixture.model.openSettings()
        XCTAssertEqual(fixture.opener.openCount, 1)
        XCTAssertEqual(
            fixture.model.step, .deniedOpenSettings, "still denied until the user changes it")
    }

    func testDrivingPermissionNeverMutatesAnAlarm() async {
        let fixture = makeFixture(auth: .denied)
        await fixture.model.refresh()
        await fixture.model.requestAfterExplanation()
        await fixture.model.openSettings()
        XCTAssertTrue(fixture.adapter.scheduledRequests.isEmpty)
        XCTAssertTrue(fixture.adapter.cancelledAlarmIDs.isEmpty)
        XCTAssertTrue(
            fixture.adapter.snoozeCalls.isEmpty,
            "the permission UI holds no alarm authority (#8/#10)")
    }
}
