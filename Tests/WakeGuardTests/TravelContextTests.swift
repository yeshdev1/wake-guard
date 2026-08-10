import XCTest

@testable import WakeGuard

/// WG-101: the travel context model. Verifies the **confirmed** system zone is separate from
/// **optional** location corroboration, that certainty + timestamps are represented, and — the safety
/// point — that a zone change alone (which a VPN or a manual clock change also produces) is **never**
/// mistaken for real travel: only a genuine significant-location change raises the certainty.
final class TravelContextTests: XCTestCase {

    private let detectedAt = Date(timeIntervalSince1970: 2_000_000)

    private func change() throws -> TimeZoneChange {
        TimeZoneChange(
            previous: try IANATimeZone(identifier: "America/New_York"),
            current: try IANATimeZone(identifier: "Europe/Paris"))
    }

    func testZoneChangeAloneIsAmbiguousNotTreatedAsTravel() throws {
        let context = TravelContext(zoneChange: try change(), detectedAt: detectedAt, location: nil)
        XCTAssertEqual(
            context.certainty, .zoneChangeOnly,
            "a zone change with no location corroboration is ambiguous — could be a VPN/manual change"
        )
    }

    func testSignificantLocationChangeCorroboratesTravel() throws {
        let context = TravelContext(
            zoneChange: try change(), detectedAt: detectedAt,
            location: LocationContext(significantLocationChanged: true, observedAt: detectedAt))
        XCTAssertEqual(context.certainty, .corroboratedByLocation)
    }

    func testLocationPresentButNoMovementStaysAmbiguous() throws {
        // Location is available but reports no significant movement — e.g. a VPN moved the system zone
        // while the user stayed put. Network/VPN is not location, so this must not corroborate travel.
        let context = TravelContext(
            zoneChange: try change(), detectedAt: detectedAt,
            location: LocationContext(significantLocationChanged: false, observedAt: detectedAt))
        XCTAssertEqual(
            context.certainty, .zoneChangeOnly,
            "location without movement does not corroborate travel")
    }

    func testConfirmedZoneAndTimestampsAreRepresented() throws {
        let observedAt = detectedAt.addingTimeInterval(5)
        let context = TravelContext(
            zoneChange: try change(), detectedAt: detectedAt,
            location: LocationContext(significantLocationChanged: true, observedAt: observedAt))
        XCTAssertEqual(context.zoneChange.previous.identifier, "America/New_York")
        XCTAssertEqual(context.zoneChange.current.identifier, "Europe/Paris")
        XCTAssertEqual(context.detectedAt, detectedAt)
        XCTAssertEqual(context.location?.observedAt, observedAt)
    }

    func testRoundTripsThroughCodable() throws {
        let context = TravelContext(
            zoneChange: try change(), detectedAt: detectedAt,
            location: LocationContext(significantLocationChanged: true, observedAt: detectedAt))
        let data = try JSONEncoder().encode(context)
        XCTAssertEqual(try JSONDecoder().decode(TravelContext.self, from: data), context)
    }

    func testLocationContextStoresNoCoordinates() {
        // #41: the coarse corroboration reveals nothing about WHERE the user is — only a movement bool +
        // a timestamp, never latitude/longitude/coordinates.
        let mirror = Mirror(
            reflecting: LocationContext(significantLocationChanged: true, observedAt: detectedAt))
        XCTAssertEqual(
            Set(mirror.children.compactMap(\.label)), ["significantLocationChanged", "observedAt"],
            "coarse: only a movement bool + timestamp — no coordinates (#41)")
    }
}
