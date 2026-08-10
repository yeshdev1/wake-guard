import XCTest

@testable import WakeGuard

/// WG-100: the system time-zone observer. Verifies the detector records previous→current on a real
/// change, is **idempotent** on repeats, seeds a baseline on first observation, **catches a change
/// missed while closed** (launch reconciliation via a pre-seeded store), and that the UserDefaults store
/// round-trips and fails closed on a corrupt value. (The `NSSystemTimeZoneDidChange` subscription in
/// `SystemTimeZoneMonitor` is the device-only framework touch-point; the detection logic tested here is
/// what it drives.)
final class TimeZoneObserverTests: XCTestCase {

    private func iana(_ identifier: String) throws -> IANATimeZone {
        try IANATimeZone(identifier: identifier)
    }

    func testFirstObservationSeedsBaselineWithNoChange() throws {
        let store = InMemoryTimeZoneStateStore()
        let detector = TimeZoneChangeDetector(store: store)
        XCTAssertNil(
            detector.observe(current: try iana("America/New_York")),
            "the first observation records a baseline, not a change")
        XCTAssertEqual(store.lastKnownZone(), try iana("America/New_York"))
    }

    func testRepeatedSameZoneIsIdempotent() throws {
        let store = InMemoryTimeZoneStateStore(try iana("Europe/London"))
        let detector = TimeZoneChangeDetector(store: store)
        XCTAssertNil(detector.observe(current: try iana("Europe/London")))
        XCTAssertNil(
            detector.observe(current: try iana("Europe/London")),
            "a repeated notification for the same zone yields no change")
    }

    func testDifferentZoneRecordsPreviousAndCurrent() throws {
        let store = InMemoryTimeZoneStateStore(try iana("America/New_York"))
        let detector = TimeZoneChangeDetector(store: store)
        let change = try XCTUnwrap(detector.observe(current: try iana("Europe/Paris")))
        XCTAssertEqual(change.previous, try iana("America/New_York"))
        XCTAssertEqual(change.current, try iana("Europe/Paris"))
        XCTAssertEqual(
            store.lastKnownZone(), try iana("Europe/Paris"), "the new zone becomes the baseline")
    }

    func testLaunchReconciliationCatchesAChangeMissedWhileClosed() throws {
        // The app was last in Tokyo (persisted), then closed; the user flew to LA; on launch the current
        // zone is LA. The detector reports the missed Tokyo → LA change — this is launch reconciliation.
        let store = InMemoryTimeZoneStateStore(try iana("Asia/Tokyo"))
        let detector = TimeZoneChangeDetector(store: store)
        let change = try XCTUnwrap(detector.observe(current: try iana("America/Los_Angeles")))
        XCTAssertEqual(
            change,
            TimeZoneChange(
                previous: try iana("Asia/Tokyo"), current: try iana("America/Los_Angeles")))
    }

    func testAfterAChangeTheSameZoneDoesNotReReport() throws {
        let store = InMemoryTimeZoneStateStore(try iana("America/New_York"))
        let detector = TimeZoneChangeDetector(store: store)
        _ = detector.observe(current: try iana("Europe/Paris"))
        XCTAssertNil(
            detector.observe(current: try iana("Europe/Paris")),
            "once recorded, the same zone is idempotent")
    }

    func testUserDefaultsStoreRoundTripsAndFailsClosedOnACorruptValue() throws {
        let suiteName = "wg.test.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsTimeZoneStateStore(suite)

        XCTAssertNil(store.lastKnownZone(), "empty by default")
        store.setLastKnownZone(try iana("Australia/Sydney"))
        XCTAssertEqual(store.lastKnownZone(), try iana("Australia/Sydney"))

        // A stored value that is no longer a valid IANA identifier fails closed to nil (re-baseline).
        suite.set("GMT+0530", forKey: "wg.travel.lastKnownTimeZone")
        XCTAssertNil(store.lastKnownZone(), "a non-IANA stored value fails closed, never crashes")
    }
}
