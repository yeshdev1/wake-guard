import XCTest

@testable import WakeGuard

/// WG-162: the Settings view-model. Verifies availability is **visible in Settings** (a refresh yields the
/// right copy) and that it **tracks live changes** — flipping availability and refreshing replaces the
/// copy, so a user who enables Apple Intelligence sees the row update.
@MainActor
final class AIAvailabilityModelTests: XCTestCase {

    func testStatusIsNilBeforeFirstRefresh() {
        let model = AIAvailabilityModel(provider: StubModelAvailabilityProvider(.available))
        XCTAssertNil(model.status)
    }

    func testRefreshShowsOnCopyWhenAvailable() {
        let model = AIAvailabilityModel(provider: StubModelAvailabilityProvider(.available))
        model.refresh()
        XCTAssertEqual(model.status?.isAvailable, true)
        XCTAssertTrue(model.decision.aiFeaturesEnabled)
    }

    func testRefreshShowsFallbackCopyWhenUnavailable() {
        let provider = StubModelAvailabilityProvider(.unavailable(.appleIntelligenceNotEnabled))
        let model = AIAvailabilityModel(provider: provider)
        model.refresh()
        XCTAssertEqual(model.status?.isAvailable, false)
        XCTAssertFalse(model.decision.aiFeaturesEnabled)
        XCTAssertEqual(model.decision.unavailabilityReason, .appleIntelligenceNotEnabled)
    }

    func testRefreshReflectsAProviderStateChange() {
        let provider = StubModelAvailabilityProvider(.unavailable(.modelNotReady))
        let model = AIAvailabilityModel(provider: provider)
        model.refresh()
        XCTAssertEqual(model.status?.isAvailable, false)

        provider.set(.available)
        model.refresh()
        XCTAssertEqual(model.status?.isAvailable, true)
    }
}
