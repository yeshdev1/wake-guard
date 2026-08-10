import XCTest

@testable import WakeGuard

/// WG-141: contextual EventKit authorization. Verifies **full read access is requested only when the user
/// enables calendar planning** (reading the current state never prompts), that a **denied state is
/// useful** (planning degrades, the app stays functional; write-only counts as denied for reading), and
/// the state mapping. The specific purpose string lives in `project.yml`.
final class CalendarAuthorizationCoordinatorTests: XCTestCase {

    // MARK: state mapping

    func testAccessStateMapsFromStatus() {
        XCTAssertEqual(CalendarAccessState(status: .fullAccess), .granted)
        XCTAssertEqual(CalendarAccessState(status: .notDetermined), .notDetermined)
        for status in [CalendarAuthorizationStatus.denied, .restricted, .writeOnly] {
            XCTAssertEqual(
                CalendarAccessState(status: status), .denied,
                "\(status) can't read events → denied for planning")
        }
    }

    // MARK: access is requested only on opt-in

    func testReadingCurrentStateNeverPrompts() async {
        let provider = RecordingCalendarAuthorizationProvider(status: .notDetermined)
        let coordinator = CalendarAuthorizationCoordinator(provider: provider)
        let state = await coordinator.currentState()
        XCTAssertEqual(state, .notDetermined)
        let requests = await provider.requestCount
        XCTAssertEqual(requests, 0, "rendering the banner must not prompt")
    }

    func testRequestAccessForPlanningIsTheOnlyRequestPath() async {
        let provider = RecordingCalendarAuthorizationProvider(
            status: .notDetermined, afterRequest: .fullAccess)
        let coordinator = CalendarAuthorizationCoordinator(provider: provider)
        let state = await coordinator.requestAccessForPlanning()
        XCTAssertEqual(state, .granted)
        let requests = await provider.requestCount
        XCTAssertEqual(requests, 1, "full access is requested exactly once, on the enable action")
    }

    // MARK: denied is useful; only full access enables planning

    func testDeniedAccessDegradesPlanningWithoutBlockingTheApp() async {
        let coordinator = CalendarAuthorizationCoordinator(
            provider: RecordingCalendarAuthorizationProvider(
                status: .notDetermined, afterRequest: .denied))
        let state = await coordinator.requestAccessForPlanning()
        XCTAssertEqual(state, .denied)
        XCTAssertFalse(
            coordinator.isPlanningAvailable(state), "planning is unavailable but the app works")
    }

    func testWriteOnlyIsDeniedForReading() async {
        let coordinator = CalendarAuthorizationCoordinator(
            provider: RecordingCalendarAuthorizationProvider(status: .writeOnly))
        let state = await coordinator.currentState()
        XCTAssertEqual(state, .denied)
        XCTAssertFalse(coordinator.isPlanningAvailable(state))
    }

    func testPlanningAvailableOnlyForGranted() {
        let coordinator = CalendarAuthorizationCoordinator(
            provider: RecordingCalendarAuthorizationProvider())
        XCTAssertTrue(coordinator.isPlanningAvailable(.granted))
        XCTAssertFalse(coordinator.isPlanningAvailable(.denied))
        XCTAssertFalse(coordinator.isPlanningAvailable(.notDetermined))
    }
}
