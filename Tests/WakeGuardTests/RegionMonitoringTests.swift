import XCTest

@testable import WakeGuard

/// WG-103: optional region-monitoring rules. Verifies explicit **enable/disable** (off by default →
/// `.unknown` safe fallback), that boundary noise is **debounced** (a flip that reverses before the
/// dwell is discarded; an unsettled crossing yields no decision), the dwell clamp, and — the safety pin
/// — that region types hold **no alarm authority** (a region state can never suppress a critical alarm).
final class RegionMonitoringTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 2_000_000)
    private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

    func testADisabledRuleYieldsUnknownSafeFallback() {
        let rule = RegionMonitoringRule(identifier: "home")  // disabled by default
        XCTAssertFalse(rule.isEnabled, "region monitoring is opt-in — off by default")
        XCTAssertEqual(
            rule.stableState(from: [RegionEvent(state: .inside, at: t0)], now: at(300)), .unknown,
            "a disabled rule drives no decision — the safe fallback")
    }

    func testAnEnteredRegionThatDwellsBecomesInside() {
        let rule = RegionMonitoringRule(identifier: "home", isEnabled: true, dwellTime: 60)
        let events = [
            RegionEvent(state: .outside, at: t0), RegionEvent(state: .inside, at: at(100)),
        ]
        XCTAssertEqual(
            rule.stableState(from: events, now: at(200)), .inside, "a real entry after dwelling")
    }

    func testABriefFlickerIsDebouncedNotCommitted() {
        // The device is outside, briefly flickers inside for 5s, then stays outside — the flicker must
        // not flip the state to inside.
        let rule = RegionMonitoringRule(identifier: "home", isEnabled: true, dwellTime: 60)
        let events = [
            RegionEvent(state: .outside, at: t0),
            RegionEvent(state: .inside, at: at(100)),  // flicker …
            RegionEvent(state: .outside, at: at(105)),  // … reverses within 5s
        ]
        XCTAssertEqual(
            rule.stableState(from: events, now: at(200)), .outside,
            "a boundary flicker that reverses before the dwell is noise, not a state change")
    }

    func testACrossingThatHasNotYetDwelledStaysUnknown() {
        let rule = RegionMonitoringRule(identifier: "home", isEnabled: true, dwellTime: 60)
        XCTAssertEqual(
            rule.stableState(from: [RegionEvent(state: .inside, at: t0)], now: at(30)), .unknown,
            "an unsettled crossing (30 s < 60 s dwell) yields no decision")
    }

    func testDwellTimeIsClampedToASafeMinimum() {
        XCTAssertEqual(
            RegionMonitoringRule(identifier: "h", isEnabled: true, dwellTime: 1).dwellTime, 60,
            "a too-short dwell can't disable debouncing")
        XCTAssertEqual(
            RegionMonitoringRule(identifier: "h", isEnabled: true, dwellTime: .nan).dwellTime, 60)
        XCTAssertEqual(
            RegionMonitoringRule(identifier: "h", isEnabled: true, dwellTime: 120).dwellTime, 120)
    }

    func testUnsortedEventsAreOrderedBeforeDebouncing() {
        // A geofence callback order isn't trusted — shuffled events must fold to the same stable state
        // as their chronological order (here the genuinely-latest dwelled state is `.inside`).
        let rule = RegionMonitoringRule(identifier: "home", isEnabled: true, dwellTime: 60)
        let shuffled = [
            RegionEvent(state: .inside, at: at(200)),  // latest, but listed first
            RegionEvent(state: .outside, at: at(100)),
        ]
        XCTAssertEqual(
            rule.stableState(from: shuffled, now: at(1000)), .inside,
            "out-of-order events must not invert the debounced state")
    }

    func testAnEventDatedAfterNowIsIgnored() {
        // Backward clock correction: the latest crossing is dated in the future relative to `now`, so it
        // hasn't happened yet — it can't commit a confident state, and the unsettled present → unknown.
        let rule = RegionMonitoringRule(identifier: "home", isEnabled: true, dwellTime: 60)
        let events = [
            RegionEvent(state: .outside, at: t0), RegionEvent(state: .inside, at: at(100)),
        ]
        XCTAssertEqual(
            rule.stableState(from: events, now: at(50)), .unknown,
            "a future-dated event (backward clock) yields the safe fallback, not a stale commit")
    }

    func testASignalLossInterruptsTheDwell() {
        // An `.unknown` (lost region signal) caps the preceding state's measured hold, so a state that
        // wasn't sustained *before* the signal dropped never commits — bias toward the safe fallback.
        let rule = RegionMonitoringRule(identifier: "home", isEnabled: true, dwellTime: 60)
        let events = [
            RegionEvent(state: .outside, at: t0),
            RegionEvent(state: .inside, at: at(100)),  // held only 30 s …
            RegionEvent(state: .unknown, at: at(130)),  // … before the signal dropped
            RegionEvent(state: .outside, at: at(1000)),
        ]
        XCTAssertEqual(
            rule.stableState(from: events, now: at(2000)), .outside,
            "a signal loss interrupts the inside dwell — it must not commit across the gap")
    }

    func testRegionStateDecodesUnknownRawValueFailClosed() throws {
        // #27: an unrecognized persisted raw value resolves to `.unknown`, never a confident state.
        XCTAssertEqual(
            try JSONDecoder().decode(RegionState.self, from: Data("\"teleported\"".utf8)), .unknown)
        XCTAssertEqual(
            try JSONDecoder().decode(RegionState.self, from: Data("\"inside\"".utf8)), .inside)
    }

    func testRegionRuleRoundTripsThroughCodable() throws {
        let rule = RegionMonitoringRule(identifier: "home", isEnabled: true, dwellTime: 90)
        XCTAssertEqual(
            try JSONDecoder().decode(
                RegionMonitoringRule.self, from: try JSONEncoder().encode(rule)), rule)
    }

    func testRegionTypesReferenceNoAlarmAuthority() {
        // Region monitoring is advisory and holds no alarm authority — its fields are a plain
        // identifier + enable flag + dwell, nothing referencing an alarm/criticality/command — so it can
        // never suppress a critical alarm (#8/#9); the safe fallback keeps it ringing.
        let mirror = Mirror(reflecting: RegionMonitoringRule(identifier: "home"))
        XCTAssertEqual(
            Set(mirror.children.compactMap(\.label)), ["identifier", "isEnabled", "dwellTime"])
    }
}
