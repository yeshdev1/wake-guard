import XCTest

@testable import WakeGuard

/// WG-109: location permission education + controls. Verifies the **approximate purpose and battery
/// behavior are explained**, the **feature works without permission** (a denied status still lets the
/// user use the control, and it's independent of the OS permission), and the **user can disable
/// monitoring** (the persisted `locationContextEnabled` control toggles both ways and touches nothing
/// else). A failed save never misreports the persisted state.
@MainActor
final class LocationMonitoringModelTests: XCTestCase {

    private func makeModel(
        settings: AppSettings = .default, status: LocationAuthorizationStatus = .authorizedWhenInUse
    ) -> (LocationMonitoringModel, InMemorySettingsRepository) {
        let repo = InMemorySettingsRepository(settings)
        let model = LocationMonitoringModel(
            settings: repo,
            locationSource: InMemorySignificantLocationSource(status: status, lastChange: nil))
        return (model, repo)
    }

    // MARK: approximate purpose + battery behavior are explained

    func testEducationExplainsApproximatePurposeAndBatteryBehavior() {
        let education = LocationEducation.standard
        XCTAssertTrue(education.purpose.contains("approximate"))
        XCTAssertTrue(education.purpose.contains("time-zone"))
        XCTAssertTrue(education.batteryBehavior.contains("GPS"))
        XCTAssertTrue(education.batteryBehavior.contains("battery"))
        XCTAssertTrue(education.worksWithoutPermission.lowercased().contains("optional"))
        XCTAssertTrue(education.worksWithoutPermission.contains("even if you never grant"))
    }

    // MARK: reads persisted control + status

    func testRefreshReadsPersistedControlAndStatus() async {
        var settings = AppSettings.default
        settings.locationContextEnabled = true
        let (model, _) = makeModel(settings: settings, status: .authorizedAlways)
        await model.refresh()
        XCTAssertTrue(model.isMonitoringEnabled)
        XCTAssertEqual(model.authorizationStatus, .authorizedAlways)
    }

    // MARK: user can enable / disable monitoring (persisted)

    func testUserCanEnableMonitoringAndItPersists() async throws {
        let (model, repo) = makeModel()
        await model.setMonitoringEnabled(true)
        XCTAssertTrue(model.isMonitoringEnabled)
        let saved = try await repo.settings()
        XCTAssertTrue(saved.locationContextEnabled)
        XCTAssertFalse(model.saveDidFail)
    }

    func testUserCanDisableMonitoringAndItPersists() async throws {
        var settings = AppSettings.default
        settings.locationContextEnabled = true
        let (model, repo) = makeModel(settings: settings)
        await model.refresh()
        XCTAssertTrue(model.isMonitoringEnabled)
        await model.setMonitoringEnabled(false)
        XCTAssertFalse(model.isMonitoringEnabled)
        let saved = try await repo.settings()
        XCTAssertFalse(saved.locationContextEnabled)
    }

    // MARK: the feature works without permission

    func testDeniedPermissionStillLetsTheUserUseTheControl() async throws {
        // Permission denied → the control still functions and is independent of the OS permission; travel
        // detection runs regardless (WG-100). The app works without location.
        let (model, repo) = makeModel(status: .denied)
        await model.refresh()
        XCTAssertEqual(model.authorizationStatus, .denied)
        XCTAssertFalse(model.authorizationStatus?.canMonitor ?? true)
        await model.setMonitoringEnabled(true)
        XCTAssertTrue(model.isMonitoringEnabled)
        let saved = try await repo.settings()
        XCTAssertTrue(saved.locationContextEnabled)
    }

    // MARK: the control is scoped (no alarm authority) and save-failure is honest

    func testTogglingMonitoringChangesOnlyTheLocationControl() async throws {
        let (model, repo) = makeModel()
        await model.setMonitoringEnabled(true)
        var expected = AppSettings.default
        expected.locationContextEnabled = true
        let saved = try await repo.settings()
        XCTAssertEqual(
            saved, expected, "only the location control changes — no other flag or alarm state")
    }

    func testSaveFailureLeavesStateAtPersistedTruth() async {
        let model = LocationMonitoringModel(
            settings: FailingSettingsRepository(),
            locationSource: InMemorySignificantLocationSource())
        await model.setMonitoringEnabled(true)
        XCTAssertFalse(
            model.isMonitoringEnabled, "a failed save must not lie about the persisted state")
        XCTAssertTrue(model.saveDidFail)
    }
}

/// A `SettingsRepository` whose `save` always fails — to prove a save error leaves the control at the
/// persisted truth rather than optimistically flipping it.
private struct FailingSettingsRepository: SettingsRepository {
    func settings() async throws -> AppSettings { .default }
    func save(_ settings: AppSettings) async throws { throw CancellationError() }
}
