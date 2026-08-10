import XCTest

@testable import WakeGuard

/// WG-121: contextual HealthKit authorization. Verifies **only the plan's necessary read types are
/// requested**, that **denied and partial access states are supported** (a coarse summary distinguishes
/// granted / partial / denied / notDetermined / unavailable), and that the **app remains functional** —
/// the optional readiness feature degrades in every non-granted state while nothing here touches alarms.
final class HealthAuthorizationCoordinatorTests: XCTestCase {

    // MARK: only necessary read types are requested

    func testRequestsExactlyThePlansTypesAndNoMore() async {
        let provider = RecordingHealthAuthorizationProvider(statuses: [.sleepAnalysis: .authorized])
        let coordinator = HealthAuthorizationCoordinator(provider: provider)
        XCTAssertEqual(coordinator.requestedTypes, [.sleepAnalysis])
        _ = await coordinator.requestAccess()
        let requested = await provider.lastRequested
        XCTAssertEqual(
            requested, [.sleepAnalysis], "requests exactly the data-minimization plan's types")
    }

    func testUnavailableDeviceMakesNoRequest() async {
        let provider = RecordingHealthAuthorizationProvider(available: false)
        let coordinator = HealthAuthorizationCoordinator(provider: provider)
        let summary = await coordinator.requestAccess()
        XCTAssertEqual(summary, .unavailable)
        let requested = await provider.lastRequested
        XCTAssertNil(requested, "no authorization is requested when HealthKit is unavailable")
    }

    // MARK: denied / partial / granted are supported

    func testAllAuthorizedIsGranted() async {
        let coordinator = HealthAuthorizationCoordinator(
            provider: RecordingHealthAuthorizationProvider(statuses: [.sleepAnalysis: .authorized]))
        let summary = await coordinator.requestAccess()
        XCTAssertEqual(summary, .granted)
        XCTAssertTrue(coordinator.isReadinessAvailable(summary))
    }

    func testDeclinedIsDenied() async {
        let coordinator = HealthAuthorizationCoordinator(
            provider: RecordingHealthAuthorizationProvider(statuses: [.sleepAnalysis: .denied]))
        let summary = await coordinator.requestAccess()
        XCTAssertEqual(summary, .denied)
        XCTAssertFalse(coordinator.isReadinessAvailable(summary))
    }

    func testRestrictedEnvironmentIsDenied() async {
        let coordinator = HealthAuthorizationCoordinator(
            provider: RecordingHealthAuthorizationProvider(statuses: [.sleepAnalysis: .restricted]))
        let summary = await coordinator.requestAccess()
        XCTAssertEqual(summary, .denied)
    }

    func testNeverAskedIsNotDetermined() async {
        // No canned status → the provider reports notDetermined for the type.
        let coordinator = HealthAuthorizationCoordinator(
            provider: RecordingHealthAuthorizationProvider())
        let summary = await coordinator.requestAccess()
        XCTAssertEqual(summary, .notDetermined)
        XCTAssertFalse(coordinator.isReadinessAvailable(summary))
    }

    // MARK: the coarse summary folds counts correctly (partial is supported)

    func testSummaryFoldsRequestedVsAuthorizedCounts() {
        XCTAssertEqual(
            HealthAccessSummary.of(requested: 2, authorized: 2, anyDenied: false), .granted)
        XCTAssertEqual(
            HealthAccessSummary.of(requested: 2, authorized: 1, anyDenied: false), .partial)
        XCTAssertEqual(
            HealthAccessSummary.of(requested: 2, authorized: 1, anyDenied: true), .partial)
        XCTAssertEqual(
            HealthAccessSummary.of(requested: 2, authorized: 0, anyDenied: true), .denied)
        XCTAssertEqual(
            HealthAccessSummary.of(requested: 2, authorized: 0, anyDenied: false), .notDetermined)
        XCTAssertEqual(
            HealthAccessSummary.of(requested: 0, authorized: 0, anyDenied: true), .notDetermined)
    }

    // MARK: the app remains functional — the readiness feature degrades, alarms don't

    func testOnlyGrantedOrPartialEnablesReadiness() {
        let coordinator = HealthAuthorizationCoordinator(
            provider: RecordingHealthAuthorizationProvider())
        XCTAssertTrue(coordinator.isReadinessAvailable(.granted))
        XCTAssertTrue(coordinator.isReadinessAvailable(.partial))
        for summary in [HealthAccessSummary.unavailable, .notDetermined, .denied] {
            XCTAssertFalse(
                coordinator.isReadinessAvailable(summary),
                "\(summary) degrades the optional readiness feature — the app stays functional")
        }
    }
}
