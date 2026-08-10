import XCTest

@testable import WakeGuard

/// WG-102: the low-power significant-location source. Verifies the **staleness filter** rejects the
/// cached/stale sample Core Location delivers first (and future-dated glitches), that a **denied** source
/// reports no change so travel detection **falls back to the time-zone observer** (WG-100) unbroken, and
/// the authorization mapping. (The real `CoreLocationSignificantLocationAdapter` uses only
/// significant-location monitoring — never continuous GPS — which is a device/code-review property, not
/// a unit test.)
final class SignificantLocationTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 2_000_000)

    // MARK: - Freshness filter (cached-sample rejection)

    func testAFreshSampleIsAccepted() {
        XCTAssertTrue(SignificantLocationFilter.isFresh(now.addingTimeInterval(-60), now: now))
    }

    func testACachedStaleSampleIsRejected() {
        // Core Location delivers a cached location first — older than the window → rejected.
        XCTAssertFalse(SignificantLocationFilter.isFresh(now.addingTimeInterval(-3_600), now: now))
    }

    func testAFutureDatedSampleIsRejected() {
        XCTAssertFalse(SignificantLocationFilter.isFresh(now.addingTimeInterval(60), now: now))
    }

    func testTheFreshnessWindowBoundaryIsInclusive() {
        let maxAge = SignificantLocationFilter.defaultMaxAge
        XCTAssertTrue(SignificantLocationFilter.isFresh(now.addingTimeInterval(-maxAge), now: now))
        XCTAssertFalse(
            SignificantLocationFilter.isFresh(now.addingTimeInterval(-maxAge - 1), now: now))
    }

    // MARK: - Denied permission preserves time-zone functionality

    func testDeniedSourceReportsNoChange() async {
        let source = InMemorySignificantLocationSource(status: .denied, lastChange: nil)
        let status = await source.authorizationStatus()
        XCTAssertFalse(status.canMonitor, "denied → cannot monitor")
        let change = await source.lastSignificantChange()
        XCTAssertNil(change, "denied → no significant-location change")
    }

    func testTimeZoneTravelDetectionIsUnaffectedByADeniedLocationSource() throws {
        // The time-zone observer (WG-100) has no location dependency — a change is still detected, and a
        // travel context with no location corroboration is simply lower-certainty (WG-101), never broken.
        // This is the "denied permission preserves time-zone functionality" guarantee.
        let store = InMemoryTimeZoneStateStore(try IANATimeZone(identifier: "America/New_York"))
        let detector = TimeZoneChangeDetector(store: store)
        let change = try XCTUnwrap(
            detector.observe(current: try IANATimeZone(identifier: "Asia/Tokyo")))
        let context = TravelContext(zoneChange: change, detectedAt: now, location: nil)
        XCTAssertEqual(
            context.certainty, .zoneChangeOnly, "travel still detected, just uncorroborated")
    }

    // MARK: - Authorization mapping

    func testOnlyWhenInUseOrAlwaysCanMonitor() {
        XCTAssertTrue(LocationAuthorizationStatus.authorizedWhenInUse.canMonitor)
        XCTAssertTrue(LocationAuthorizationStatus.authorizedAlways.canMonitor)
        for status in [LocationAuthorizationStatus.notDetermined, .restricted, .denied] {
            XCTAssertFalse(status.canMonitor, "\(status) cannot monitor")
        }
    }
}
