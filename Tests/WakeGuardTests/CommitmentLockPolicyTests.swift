import Foundation
import XCTest

@testable import WakeGuard

/// WG-288: the commitment lock enforced by `DefaultAlarmPolicyEngine` (amended invariant #6, WG-293 — human
/// approved). Inside the lock every destructive command on a critical wake-challenge alarm is **rejected**,
/// and confirmation does NOT lift it (the whole point); outside the lock the existing #6 confirmation
/// behaviour is unchanged; the challenge pass itself is never blocked.
final class CommitmentLockPolicyTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 289)

    /// Weekly all-days 07:00 UTC critical alarm with a walk challenge — locks from 06:00 UTC.
    private func makeAlarm(critical: Bool = true) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule,
            criticality: critical ? .critical : .standard,
            challengePolicy: .walk(try .standard()), createdAt: epoch, updatedAt: epoch)
    }

    private func iso(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func makeEngine(
        now: Date, pendingFire: Date? = nil
    ) throws -> (DefaultAlarmPolicyEngine, CoreDataAlarmRepository) {
        let alarms = CoreDataAlarmRepository(try PersistenceController(inMemory: true))
        let engine = DefaultAlarmPolicyEngine(
            alarms: alarms, clock: TestClock(now: now), deviceTimeZone: { .gmt },
            pendingUnsatisfiedFireTime: { _ in pendingFire })
        return (engine, alarms)
    }

    func testLockedDestructiveCommandsAreRejectedAndConfirmationDoesNotLift() async throws {
        // 06:30 — 30 minutes before the 07:00 fire, inside the 60-minute lock.
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:30:00Z"))
        let alarm = try makeAlarm()
        try await alarms.save(alarm)

        for command in [AlarmCommand.delete(alarm.id), .disable(alarm.id), .update(alarm)] {
            let unconfirmed = await engine.authorize(
                command, from: .userInterface, userConfirmed: false)
            guard case .rejected(let reason) = unconfirmed else {
                return XCTFail("\(command) must be rejected while locked")
            }
            XCTAssertTrue(reason.contains("locked"), "the copy names the lock")
            // The defining semantic: unlike #6 confirmation, confirming does NOT lift the lock.
            let confirmed = await engine.authorize(
                command, from: .userInterface, userConfirmed: true)
            guard case .rejected = confirmed else {
                return XCTFail("confirmation must not lift the lock for \(command)")
            }
        }
    }

    func testOutsideTheWindowTheExistingConfirmationBehaviourIsUnchanged() async throws {
        // 04:00 — three hours out: not locked; a critical delete stays confirmable (#6 as before).
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T04:00:00Z"))
        let alarm = try makeAlarm()
        try await alarms.save(alarm)

        let decision = await engine.authorize(
            .delete(alarm.id), from: .userInterface, userConfirmed: false)
        guard case .needsConfirmation = decision else {
            return XCTFail("outside the lock a critical delete is confirmable, not rejected")
        }
        let confirmed = await engine.authorize(
            .delete(alarm.id), from: .userInterface, userConfirmed: true)
        XCTAssertEqual(confirmed, .authorized, "confirmation still works outside the lock")
    }

    func testTheChallengePassIsNeverBlockedByTheLock() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:30:00Z"))
        let alarm = try makeAlarm()
        try await alarms.save(alarm)

        let pass = await engine.authorize(
            .markChallengePassed(alarm.id), from: .userInterface, userConfirmed: false)
        XCTAssertEqual(
            pass, .authorized, "the wake path must always be able to stop the ring (#24)")
    }

    func testStandardChallengeAlarmInsideTheWindowIsNotLocked() async throws {
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T06:30:00Z"))
        let alarm = try makeAlarm(critical: false)
        try await alarms.save(alarm)

        let decision = await engine.authorize(
            .delete(alarm.id), from: .userInterface, userConfirmed: false)
        XCTAssertEqual(decision, .authorized, "the lock is critical-only (WG-293 scope guard)")
    }

    func testUnsatisfiedFireLocksThroughTheRingWindowThenReleases() async throws {
        let fire = try iso("2026-08-17T07:00:00Z")
        let alarm = try makeAlarm()

        // 07:10, wake unsatisfied: the next occurrence is ~tomorrow, but the ring window locks it —
        // the alarm cannot be deleted mid-ring to silence the chain.
        let (ringing, alarms) = try makeEngine(
            now: try iso("2026-08-17T07:10:00Z"), pendingFire: fire)
        try await alarms.save(alarm)
        let midRing = await ringing.authorize(
            .delete(alarm.id), from: .userInterface, userConfirmed: true)
        guard case .rejected = midRing else {
            return XCTFail("mid-ring delete must be rejected while the wake is unsatisfied")
        }

        // 07:40 — past the bounded ring window: the lock releases; #6 confirmation applies again.
        let (after, alarmsAfter) = try makeEngine(
            now: try iso("2026-08-17T07:40:00Z"), pendingFire: fire)
        try await alarmsAfter.save(alarm)
        let released = await after.authorize(
            .delete(alarm.id), from: .userInterface, userConfirmed: false)
        guard case .needsConfirmation = released else {
            return XCTFail("past the bound the alarm is changeable again (confirmable, not locked)")
        }
    }

    func testRingWindowLockIsComputedWithoutAnyPendingWiring() async throws {
        // No injected pending read: the engine derives the fired occurrence itself from the schedule
        // (WG-291 time rule), so the mid-ring lock holds with zero extra wiring.
        let (engine, alarms) = try makeEngine(now: try iso("2026-08-17T07:10:00Z"))
        let alarm = try makeAlarm()
        try await alarms.save(alarm)

        let decision = await engine.authorize(
            .delete(alarm.id), from: .userInterface, userConfirmed: true)
        guard case .rejected = decision else {
            return XCTFail("the ring-window lock must hold from the schedule alone")
        }
    }
}
