import Foundation
import XCTest

@testable import WakeGuard

/// WG-108: airport/transit and rapid zone changes. Verifies **prompt spam is suppressed** (a zone must
/// settle before it counts; rapid flips → no settled zone), the **latest reliable state wins through
/// versioning** (a higher version wins regardless of delivery order; a stale lower version is ignored),
/// and **an alarm close to firing is not destabilized** (an imminent ring defers the change). Plus the
/// clamps and the no-alarm-authority pin.
final class RapidZoneChangeGateTests: XCTestCase {

    private let gate = RapidZoneChangeGate(settleDuration: 120, imminentWindow: 900)
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

    private func iana(_ identifier: String) throws -> IANATimeZone {
        try IANATimeZone(identifier: identifier)
    }

    private func obs(_ zone: IANATimeZone, _ version: Int, _ offset: TimeInterval)
        -> VersionedZoneObservation
    {
        VersionedZoneObservation(zone: zone, version: version, observedAt: at(offset))
    }

    // MARK: prompt spam suppression

    func testRapidFlipsDoNotSettleSoNoPromptFires() throws {
        let (tokyo, newYork) = (try iana("Asia/Tokyo"), try iana("America/New_York"))
        let flapping = [obs(tokyo, 1, 0), obs(newYork, 2, 10), obs(tokyo, 3, 20)]
        // The latest observation is only 5 s old (< 120 s dwell) → still flapping → nothing settled.
        XCTAssertNil(gate.settledZone(from: flapping, now: at(25)))
    }

    func testAZoneThatHoldsLongEnoughSettles() throws {
        let (tokyo, newYork) = (try iana("Asia/Tokyo"), try iana("America/New_York"))
        let flapping = [obs(tokyo, 1, 0), obs(newYork, 2, 10), obs(tokyo, 3, 20)]
        // Once the latest zone has held >= 120 s, it settles (the flips are coalesced away).
        XCTAssertEqual(gate.settledZone(from: flapping, now: at(200)), tokyo)
    }

    func testSettleBoundaryIsInclusive() throws {
        let tokyo = try iana("Asia/Tokyo")
        XCTAssertEqual(gate.settledZone(from: [obs(tokyo, 1, 0)], now: at(120)), tokyo)
        XCTAssertNil(gate.settledZone(from: [obs(tokyo, 1, 0)], now: at(119)))
    }

    func testEmptyObservationsSettleToNothing() {
        XCTAssertNil(gate.settledZone(from: [], now: at(1000)))
    }

    // MARK: latest reliable state wins through versioning

    func testHigherVersionWinsRegardlessOfDeliveryOrder() throws {
        let (tokyo, newYork) = (try iana("Asia/Tokyo"), try iana("America/New_York"))
        // New York is the newer state (v3) but Tokyo (v1) is delivered LAST and has a LATER observedAt (a
        // delayed/stale notification). Versioning must pick New York, not the last-delivered stale Tokyo.
        let outOfOrder = [obs(newYork, 3, 0), obs(tokyo, 1, 500)]
        XCTAssertEqual(gate.settledZone(from: outOfOrder, now: at(1000)), newYork)
    }

    func testLowerVersionObservationIsIgnored() throws {
        let (tokyo, newYork) = (try iana("Asia/Tokyo"), try iana("America/New_York"))
        XCTAssertEqual(
            gate.settledZone(from: [obs(tokyo, 5, 5), obs(newYork, 2, 2)], now: at(1000)), tokyo)
    }

    func testAVersionTieResolvesDeterministicallyRegardlessOfOrder() throws {
        let (tokyo, newYork) = (try iana("Asia/Tokyo"), try iana("America/New_York"))
        // Two observations collide on the top version (v5) — a delayed re-delivery / flap / launch
        // replay. The tie resolves by newest observedAt (Tokyo @t50), the SAME winner regardless of
        // array order — never by delivery order.
        let forward = [obs(newYork, 5, 0), obs(tokyo, 5, 50)]
        let reversed = [obs(tokyo, 5, 50), obs(newYork, 5, 0)]
        XCTAssertEqual(gate.settledZone(from: forward, now: at(1000)), tokyo)
        XCTAssertEqual(
            gate.settledZone(from: reversed, now: at(1000)),
            gate.settledZone(from: forward, now: at(1000)))
    }

    // MARK: an alarm close to firing is not destabilized

    func testImminentOrOverdueAlarmDefersTheChange() {
        XCTAssertTrue(
            gate.shouldDeferForImminentAlarm(nextRing: at(800), now: at(0)), "within window")
        XCTAssertTrue(
            gate.shouldDeferForImminentAlarm(nextRing: at(900), now: at(0)), "boundary defers")
        XCTAssertTrue(
            gate.shouldDeferForImminentAlarm(nextRing: at(-60), now: at(0)), "overdue defers")
    }

    func testAFarFutureOrAbsentAlarmDoesNotDefer() {
        XCTAssertFalse(gate.shouldDeferForImminentAlarm(nextRing: at(1000), now: at(0)))
        XCTAssertFalse(gate.shouldDeferForImminentAlarm(nextRing: nil, now: at(0)))
    }

    func testAnImminentAlarmIsNotDestabilizedEvenWhenAZoneHasSettled() throws {
        // A new zone genuinely settled, yet the alarm rings in 5 min → the change must be deferred, so the
        // alarm about to ring is left exactly as scheduled (#16/#9).
        let newYork = try iana("America/New_York")
        XCTAssertEqual(gate.settledZone(from: [obs(newYork, 2, 0)], now: at(1000)), newYork)
        XCTAssertTrue(gate.shouldDeferForImminentAlarm(nextRing: at(1300), now: at(1000)))
    }

    // MARK: clamps + no alarm authority

    func testDurationsAreClampedToSafeBounds() {
        XCTAssertEqual(
            RapidZoneChangeGate(settleDuration: 5, imminentWindow: 10).settleDuration, 120)
        XCTAssertEqual(
            RapidZoneChangeGate(settleDuration: 5, imminentWindow: 10).imminentWindow, 900)
        XCTAssertEqual(
            RapidZoneChangeGate(settleDuration: .nan, imminentWindow: .infinity).settleDuration, 120
        )
        XCTAssertEqual(
            RapidZoneChangeGate(settleDuration: .nan, imminentWindow: .infinity).imminentWindow, 900
        )
        // Upper cap (a day): a pathological huge value can't permanently defer every alarm / never settle.
        XCTAssertEqual(
            RapidZoneChangeGate(settleDuration: 1e18, imminentWindow: 1e18).settleDuration, 86_400)
        XCTAssertEqual(
            RapidZoneChangeGate(settleDuration: 1e18, imminentWindow: 1e18).imminentWindow, 86_400)
        XCTAssertEqual(
            RapidZoneChangeGate(settleDuration: 200, imminentWindow: 1800).settleDuration, 200)
        XCTAssertEqual(
            RapidZoneChangeGate(settleDuration: 200, imminentWindow: 1800).imminentWindow, 1800)
    }

    func testGateHoldsNoAlarmAuthority() {
        // It yields a settled zone or a defer decision — nothing referencing an AlarmCommand/criticality.
        let mirror = Mirror(reflecting: RapidZoneChangeGate())
        XCTAssertEqual(
            Set(mirror.children.compactMap(\.label)), ["settleDuration", "imminentWindow"])
    }
}
