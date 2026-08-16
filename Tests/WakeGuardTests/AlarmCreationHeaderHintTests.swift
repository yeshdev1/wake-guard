import XCTest

@testable import WakeGuard

/// WG-300/302: the creation header's Apple Intelligence hint. Pins both the availability decision the view
/// branches on and the **reason-aware copy** (`AlarmCreationHint`): available → no hint; off-but-supported →
/// "turn it on" + Open Settings; ineligible / preparing → an honest "not available, add manually" with **no**
/// Settings button (nothing to flip). This is exactly the "tell the user they can't use the AI function and
/// ask them to enter manually" behaviour, pinned so it can't regress silently.
@MainActor
final class AlarmCreationHeaderHintTests: XCTestCase {

    private func reason(for availability: ModelAvailability) -> ModelUnavailabilityReason? {
        AIAvailabilityModel(provider: StubModelAvailabilityProvider(availability))
            .decision.unavailabilityReason
    }

    private func decision(_ reason: ModelUnavailabilityReason) -> AIAvailabilityDecision {
        AIAvailabilityDecision(aiFeaturesEnabled: false, unavailabilityReason: reason)
    }

    func testHintCopyIsReasonAwareAndOffersSettingsOnlyWhenActionable() {
        XCTAssertNil(AlarmCreationHint.hint(for: .enabled), "AI on → no hint at all")

        let off = AlarmCreationHint.hint(for: decision(.appleIntelligenceNotEnabled))
        XCTAssertEqual(off?.showsOpenSettings, true, "off-but-supported offers Open Settings")
        XCTAssertTrue(off?.message.contains("Turn it on") ?? false)

        let ineligible = AlarmCreationHint.hint(for: decision(.deviceNotEligible))
        XCTAssertEqual(
            ineligible?.showsOpenSettings, false, "nothing to turn on → no Settings button")
        XCTAssertTrue(
            ineligible?.message.lowercased().contains("doesn’t support") ?? false,
            "ineligible → honest 'this iPhone doesn't support Apple Intelligence'")
        XCTAssertTrue(
            ineligible?.message.lowercased().contains("manually") ?? false,
            "always points the user to manual entry")

        let preparing = AlarmCreationHint.hint(for: decision(.modelNotReady))
        XCTAssertEqual(preparing?.showsOpenSettings, false)
        XCTAssertTrue(preparing?.message.lowercased().contains("manually") ?? false)
    }

    func testHintShowsOnlyWhenAppleIntelligenceIsOffButSupported() {
        XCTAssertEqual(
            reason(for: .unavailable(.appleIntelligenceNotEnabled)), .appleIntelligenceNotEnabled,
            "off-but-supported → the actionable 'turn it on' hint shows")
        XCTAssertNil(reason(for: .available), "AI on → no hint")
        XCTAssertEqual(
            reason(for: .unavailable(.deviceNotEligible)), .deviceNotEligible,
            "ineligible → not the appleIntelligenceNotEnabled reason, so no 'turn it on' nudge")
        XCTAssertEqual(
            reason(for: .unavailable(.modelNotReady)), .modelNotReady,
            "still preparing → not the 'turn it on' reason")
    }

    func testDecisionIsCachedAndClearsOnRefresh() {
        // WG-303: `decision` is cached (not recomputed per read — that hit the framework every render on
        // device). It reflects the state at init, and a change is picked up only on `refresh()` (which the
        // view calls on appear / foreground), so enabling Apple Intelligence and returning clears the hint.
        let provider = StubModelAvailabilityProvider(.unavailable(.appleIntelligenceNotEnabled))
        let model = AIAvailabilityModel(provider: provider)
        XCTAssertEqual(model.decision.unavailabilityReason, .appleIntelligenceNotEnabled)
        provider.set(.available)
        XCTAssertEqual(
            model.decision.unavailabilityReason, .appleIntelligenceNotEnabled,
            "cached until refresh — no per-render framework call")
        model.refresh()
        XCTAssertNil(model.decision.unavailabilityReason, "refresh picks up the enabled state")
    }
}
