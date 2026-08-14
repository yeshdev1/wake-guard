import Foundation
import XCTest

@testable import WakeGuard

/// WG-288: the pure commitment-lock rule (amended invariant #6, WG-293). A critical + wake-challenge +
/// enabled alarm locks from 60 minutes before its fire instant, and an unsatisfied fire keeps it locked
/// through the bounded ring window; nothing else ever locks. Deterministic — `now` injected.
final class CommitmentLockTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 288)
    private let created = Date(timeIntervalSince1970: 1_700_000_000)
    private let fire = Date(timeIntervalSince1970: 1_700_100_000)

    private func makeAlarm(
        critical: Bool = true, challenge: Bool = true, enabled: Bool = true
    ) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "America/New_York")))
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", isEnabled: enabled, schedule: schedule,
            criticality: critical ? .critical : .standard,
            challengePolicy: challenge ? .walk(try .standard()) : .none,
            createdAt: created, updatedAt: created)
    }

    func testLocksExactlyAtTheWindowBoundary() throws {
        let alarm = try makeAlarm()
        XCTAssertTrue(
            CommitmentLock.isLocked(
                alarm: alarm, nextFireTime: fire, now: fire.addingTimeInterval(-3600)),
            "exactly 60 minutes out is committed")
        XCTAssertFalse(
            CommitmentLock.isLocked(
                alarm: alarm, nextFireTime: fire, now: fire.addingTimeInterval(-3601)),
            "one second earlier is still free to change")
        XCTAssertTrue(
            CommitmentLock.isLocked(
                alarm: alarm, nextFireTime: fire, now: fire.addingTimeInterval(-1)),
            "right before the fire is committed")
    }

    func testOnlyTheCriticalChallengeEnabledCombinationLocks() throws {
        let inWindow = fire.addingTimeInterval(-1800)
        for (alarm, label) in [
            (try makeAlarm(critical: false), "a standard alarm never locks"),
            (try makeAlarm(challenge: false), "a challenge-free critical alarm never locks"),
            (try makeAlarm(enabled: false), "a disabled alarm never locks"),
        ] {
            XCTAssertFalse(
                CommitmentLock.isLocked(alarm: alarm, nextFireTime: fire, now: inWindow), label)
        }
    }

    func testNoFireInstantAndClockJumpsCannotConjureALock() throws {
        let alarm = try makeAlarm()
        XCTAssertFalse(
            CommitmentLock.isLocked(alarm: alarm, nextFireTime: nil, now: created),
            "no resolvable occurrence, no pending — nothing to commit to")
        XCTAssertFalse(
            CommitmentLock.isLocked(
                alarm: alarm, nextFireTime: fire, now: fire.addingTimeInterval(60)),
            "a past fire instant without a pending wake is not a pre-window lock")
    }

    func testUnsatisfiedFireKeepsTheLockThroughTheRingWindowOnly() throws {
        let alarm = try makeAlarm()
        // The next occurrence has rolled to ~tomorrow — far outside the pre-window.
        let tomorrow = fire.addingTimeInterval(86_400)
        XCTAssertTrue(
            CommitmentLock.isLocked(
                alarm: alarm, nextFireTime: tomorrow, pendingUnsatisfiedFireTime: fire, now: fire),
            "locked from the unsatisfied fire instant")
        XCTAssertTrue(
            CommitmentLock.isLocked(
                alarm: alarm, nextFireTime: tomorrow, pendingUnsatisfiedFireTime: fire,
                now: fire.addingTimeInterval(1799)),
            "still locked just inside the ring window")
        XCTAssertFalse(
            CommitmentLock.isLocked(
                alarm: alarm, nextFireTime: tomorrow, pendingUnsatisfiedFireTime: fire,
                now: fire.addingTimeInterval(1800)),
            "the bound ends the lock — the alarm always becomes changeable again")
    }

    func testRingBoundDerivesFromTheRearmChainSoTheyNeverDrift() {
        XCTAssertEqual(RearmConfiguration.default.totalWindow, 1800)
        XCTAssertEqual(CommitmentLockConfiguration.default.ringBound, 1800)
        XCTAssertEqual(CommitmentLockConfiguration.default.window, 3600)
    }

    func testDegenerateConfigurationIsClampedNonNegative() {
        let clamped = CommitmentLockConfiguration(window: -10, ringBound: -10)
        XCTAssertEqual(clamped.window, 0)
        XCTAssertEqual(clamped.ringBound, 0)
    }
}
