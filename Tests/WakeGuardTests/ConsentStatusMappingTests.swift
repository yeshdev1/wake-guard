import Foundation
import XCTest

@testable import WakeGuard

#if canImport(UserNotifications)
    import UserNotifications
#endif
#if canImport(CoreMotion)
    import CoreMotion
#endif
#if canImport(EventKit)
    import EventKit
#endif

/// WG-180/250: the pure OS-authorization → `ConsentStatus` mapping behind the production consent provider.
/// Tested without touching a live framework by passing the raw OS enum values directly — the mapping is the
/// logic worth pinning; the framework reads themselves are device-adjacent.
final class ConsentStatusMappingTests: XCTestCase {

    func testAlarmMapping() {
        XCTAssertEqual(ConsentStatusMapping.map(alarm: .authorized), .granted)
        XCTAssertEqual(ConsentStatusMapping.map(alarm: .denied), .denied)
        XCTAssertEqual(ConsentStatusMapping.map(alarm: .restricted), .restricted)
        XCTAssertEqual(ConsentStatusMapping.map(alarm: .notDetermined), .notDetermined)
    }

    func testCloudAINeedsBothConsentAndToken() {
        XCTAssertEqual(ConsentStatusMapping.mapCloudAI(consented: true, hasToken: true), .granted)
        XCTAssertEqual(
            ConsentStatusMapping.mapCloudAI(consented: true, hasToken: false), .notDetermined)
        XCTAssertEqual(
            ConsentStatusMapping.mapCloudAI(consented: false, hasToken: true), .notDetermined)
    }

    #if canImport(UserNotifications)
        func testNotificationMapping() {
            XCTAssertEqual(ConsentStatusMapping.map(notifications: .authorized), .granted)
            XCTAssertEqual(ConsentStatusMapping.map(notifications: .provisional), .granted)
            XCTAssertEqual(ConsentStatusMapping.map(notifications: .denied), .denied)
            XCTAssertEqual(ConsentStatusMapping.map(notifications: .notDetermined), .notDetermined)
        }
    #endif

    func testLocationMapping() {
        // Location maps the domain `LocationAuthorizationStatus`, so no CoreLocation import is needed —
        // the coordinate-handling stays confined to the WG-102 adapter.
        XCTAssertEqual(ConsentStatusMapping.map(location: .authorizedWhenInUse), .granted)
        XCTAssertEqual(ConsentStatusMapping.map(location: .authorizedAlways), .granted)
        XCTAssertEqual(ConsentStatusMapping.map(location: .denied), .denied)
        XCTAssertEqual(ConsentStatusMapping.map(location: .restricted), .restricted)
        XCTAssertEqual(ConsentStatusMapping.map(location: .notDetermined), .notDetermined)
    }

    #if canImport(CoreMotion)
        func testMotionMapping() {
            XCTAssertEqual(ConsentStatusMapping.map(motion: .authorized), .granted)
            XCTAssertEqual(ConsentStatusMapping.map(motion: .denied), .denied)
            XCTAssertEqual(ConsentStatusMapping.map(motion: .restricted), .restricted)
            XCTAssertEqual(ConsentStatusMapping.map(motion: .notDetermined), .notDetermined)
        }
    #endif

    #if canImport(EventKit)
        func testCalendarMapping() {
            XCTAssertEqual(ConsentStatusMapping.map(calendar: .fullAccess), .granted)
            XCTAssertEqual(ConsentStatusMapping.map(calendar: .denied), .denied)
            XCTAssertEqual(
                ConsentStatusMapping.map(calendar: .writeOnly), .denied,
                "write-only can't read events, which is what the app needs")
            XCTAssertEqual(ConsentStatusMapping.map(calendar: .notDetermined), .notDetermined)
        }
    #endif

    func testFixedProviderIsHermeticAndConstant() async {
        let provider = FixedConsentStatusProvider(status: .granted)
        for category in ConsentCategory.allCases {
            let status = await provider.status(for: category)
            XCTAssertEqual(status, .granted, "the hermetic provider returns its fixed status")
        }
    }
}
