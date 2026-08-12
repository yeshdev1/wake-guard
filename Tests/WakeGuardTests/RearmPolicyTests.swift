import Foundation
import XCTest

@testable import WakeGuard

/// WG-283: the pure re-arm policy for the enforced walk challenge. A not-passed **critical** challenge
/// re-arms at a bounded interval until the cap, then stops — the cap is the safety bound (an alarm must
/// always be able to end, WG-285). Pure + deterministic (`now` injected).
final class RearmPolicyTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 283)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func pending(attempts: Int) -> PendingChallenge {
        PendingChallenge(alarmID: AlarmID(ids.next()), originalFireTime: now, attempts: attempts)
    }

    func testReArmsAtTheConfiguredIntervalWhileUnderTheCap() {
        let decision = RearmPolicy.next(after: now, pending: pending(attempts: 0))
        XCTAssertEqual(decision, .rearm(at: now.addingTimeInterval(120)))
    }

    func testStopsExactlyAtTheCapSoTheAlarmAlwaysEnds() {
        let config = RearmConfiguration(interval: 120, maxAttempts: 15)
        XCTAssertEqual(
            RearmPolicy.next(after: now, pending: pending(attempts: 14), config: config),
            .rearm(at: now.addingTimeInterval(120)), "one below the cap still re-arms")
        XCTAssertEqual(
            RearmPolicy.next(after: now, pending: pending(attempts: 15), config: config),
            .stop, "at the cap it stops — the alarm always ends (WG-285)")
        XCTAssertEqual(
            RearmPolicy.next(after: now, pending: pending(attempts: 99), config: config),
            .stop, "past the cap it stays stopped")
    }

    func testDefaultConfigIsEveryTwoMinutesFifteenTimes() {
        XCTAssertEqual(RearmConfiguration.default.interval, 120)
        XCTAssertEqual(RearmConfiguration.default.maxAttempts, 15)
    }

    func testCustomIntervalIsHonored() {
        let config = RearmConfiguration(interval: 300, maxAttempts: 5)
        XCTAssertEqual(
            RearmPolicy.next(after: now, pending: pending(attempts: 1), config: config),
            .rearm(at: now.addingTimeInterval(300)))
    }

    func testDegenerateConfigIsClampedAndCannotTrapTheUser() {
        // A negative interval/cap must not produce a negative delay or an unbounded loop.
        let clamped = RearmConfiguration(interval: -60, maxAttempts: -3)
        XCTAssertEqual(clamped.interval, 0)
        XCTAssertEqual(clamped.maxAttempts, 0)
        // A zero cap stops immediately — the alarm is never re-armed.
        XCTAssertEqual(
            RearmPolicy.next(after: now, pending: pending(attempts: 0), config: clamped), .stop)
    }
}
