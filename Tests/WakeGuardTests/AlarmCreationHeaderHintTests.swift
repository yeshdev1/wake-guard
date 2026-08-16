import XCTest

@testable import WakeGuard

/// WG-300: the creation header's Apple Intelligence hint condition. The header shows the actionable
/// "turn it on" nudge **only** when the model is off-but-supported (`appleIntelligenceNotEnabled`) — never
/// when AI is available, and never on an ineligible device (where there's nothing to turn on). This pins
/// the exact `AIAvailabilityModel.decision` the view branches on, so the nudge can't start showing (or stop)
/// silently. It refreshes when the reported state flips (e.g. the user enables AI and returns).
@MainActor
final class AlarmCreationHeaderHintTests: XCTestCase {

    private func reason(for availability: ModelAvailability) -> ModelUnavailabilityReason? {
        AIAvailabilityModel(provider: StubModelAvailabilityProvider(availability))
            .decision.unavailabilityReason
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

    func testHintClearsWhenAppleIntelligenceIsTurnedOn() {
        let provider = StubModelAvailabilityProvider(.unavailable(.appleIntelligenceNotEnabled))
        let model = AIAvailabilityModel(provider: provider)
        XCTAssertEqual(model.decision.unavailabilityReason, .appleIntelligenceNotEnabled)
        provider.set(.available)
        XCTAssertNil(
            model.decision.unavailabilityReason, "enabling AI clears the hint on next read")
    }
}
