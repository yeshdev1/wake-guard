import Foundation
import XCTest

@testable import WakeGuard

/// WG-144: the morning preparation profile. Verifies **preparation, travel, and safety buffers are
/// explicit**, that **defaults are editable** (and clamped to a sane range), and that computing lead time
/// **requires no location or calendar permission** — travel is a user default, and `leadTime` takes only a
/// boolean, never any location data.
final class MorningPreparationProfileTests: XCTestCase {

    private let minute: TimeInterval = 60

    // MARK: explicit buffers + editable defaults

    func testDefaultProfileHasThreeExplicitBuffers() {
        let profile = MorningPreparationProfile.default
        XCTAssertEqual(profile.preparationBuffer, 45 * minute)
        XCTAssertEqual(profile.travelBuffer, 30 * minute)
        XCTAssertEqual(profile.safetyBuffer, 10 * minute)
    }

    func testBuffersAreEditable() {
        let profile = MorningPreparationProfile(
            preparationBuffer: 60 * minute, travelBuffer: 20 * minute, safetyBuffer: 5 * minute)
        XCTAssertEqual(profile.preparationBuffer, 60 * minute)
        XCTAssertEqual(profile.travelBuffer, 20 * minute)
        XCTAssertEqual(profile.safetyBuffer, 5 * minute)
    }

    func testBuffersAreClampedToASaneRange() {
        let profile = MorningPreparationProfile(
            preparationBuffer: -100, travelBuffer: 100 * 3_600, safetyBuffer: .nan)
        XCTAssertEqual(profile.preparationBuffer, 0, "negative → 0")
        XCTAssertEqual(profile.travelBuffer, MorningPreparationProfile.maxBuffer, "huge → capped")
        XCTAssertEqual(profile.safetyBuffer, 0, "non-finite → 0")
    }

    // MARK: lead time needs no location / calendar permission

    func testLeadTimeAddsTravelOnlyWhenTheEventHasALocation() {
        let profile = MorningPreparationProfile(
            preparationBuffer: 45 * minute, travelBuffer: 30 * minute, safetyBuffer: 10 * minute)
        XCTAssertEqual(
            profile.leadTime(forEventWithLocation: true), (45 + 30 + 10) * minute,
            "prep + travel + safety")
        XCTAssertEqual(
            profile.leadTime(forEventWithLocation: false), (45 + 10) * minute,
            "no travel without a location")
    }

    func testProfileHoldsOnlyBuffersNoLocationOrPermission() {
        // Pure user configuration — its fields are the three buffers, nothing referencing location,
        // coordinates, calendar, or a permission. Lead time is a function of a boolean only.
        let mirror = Mirror(reflecting: MorningPreparationProfile.default)
        XCTAssertEqual(
            Set(mirror.children.compactMap(\.label)),
            ["preparationBuffer", "travelBuffer", "safetyBuffer"])
    }

    func testProfileRoundTripsThroughCodable() throws {
        let profile = MorningPreparationProfile.default
        XCTAssertEqual(
            try JSONDecoder().decode(
                MorningPreparationProfile.self, from: try JSONEncoder().encode(profile)),
            profile)
    }
}
