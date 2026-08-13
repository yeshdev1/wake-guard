import Foundation
import XCTest

@testable import WakeGuard

/// WG-291: the pure wake-chain spec. Member identity is deterministic per (parent, occurrence, index);
/// the family exists only for critical + wake-challenge alarms; entries march at the re-arm interval to
/// the confidential bound; `firedOccurrence` marks the live ring window and nothing else.
final class WakeChainTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 291)
    private let created = Date(timeIntervalSince1970: 1_700_000_000)
    private let occurrence = Date(timeIntervalSince1970: 1_700_100_000)

    private func makeAlarm(
        critical: Bool = true, challenge: Bool = true, enabled: Bool = true
    ) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", isEnabled: enabled, schedule: schedule,
            criticality: critical ? .critical : .standard,
            challengePolicy: challenge ? .walk(try .standard()) : .none,
            createdAt: created, updatedAt: created)
    }

    func testMemberIdentityIsDeterministicAndCollisionResistant() throws {
        let alarm = try makeAlarm()
        let id1 = WakeChain.memberID(parent: alarm.id, occurrence: occurrence, index: 1)
        XCTAssertEqual(
            id1, WakeChain.memberID(parent: alarm.id, occurrence: occurrence, index: 1),
            "same inputs, same id — idempotent scheduling depends on it")
        let variants = [
            WakeChain.memberID(parent: alarm.id, occurrence: occurrence, index: 2),
            WakeChain.memberID(
                parent: alarm.id, occurrence: occurrence.addingTimeInterval(86_400), index: 1),
            WakeChain.memberID(parent: AlarmID(ids.next()), occurrence: occurrence, index: 1),
        ]
        XCTAssertEqual(
            Set(variants + [id1]).count, 4,
            "index, occurrence, and parent each produce distinct ids — occurrences never collide")
    }

    func testFamilyExistsOnlyForCriticalChallengeAlarms() throws {
        XCTAssertTrue(
            WakeChain.requests(for: try makeAlarm(critical: false), occurrence: occurrence).isEmpty)
        XCTAssertTrue(
            WakeChain.requests(for: try makeAlarm(challenge: false), occurrence: occurrence)
                .isEmpty)
        XCTAssertFalse(WakeChain.requests(for: try makeAlarm(), occurrence: occurrence).isEmpty)
    }

    func testEntriesMarchAtTheIntervalWithParentRouting() throws {
        let alarm = try makeAlarm()
        let entries = WakeChain.requests(for: alarm, occurrence: occurrence)
        XCTAssertEqual(entries.count, RearmConfiguration.default.maxAttempts)
        for (offset, entry) in entries.enumerated() {
            XCTAssertEqual(
                entry.fireTime, occurrence.addingTimeInterval(Double(offset + 1) * 120),
                "members fire every 2 minutes behind the occurrence")
            XCTAssertEqual(entry.parentAlarmID, alarm.id, "the intent routes to the parent")
            XCTAssertTrue(entry.isCritical)
            XCTAssertNotNil(entry.requiredSteps, "members carry the Start-walk affordance")
            XCTAssertNotEqual(entry.alarmID, alarm.id)
        }
    }

    func testFiredOccurrenceMarksExactlyTheLiveRingWindow() throws {
        let alarm = try makeAlarm()
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let fire = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-17T07:00:00Z"))
        XCTAssertEqual(
            WakeChain.firedOccurrence(
                for: alarm, now: fire.addingTimeInterval(600), deviceTimeZone: zone),
            fire, "ten minutes after the fire the window is live")
        XCTAssertNil(
            WakeChain.firedOccurrence(
                for: alarm, now: fire.addingTimeInterval(-60), deviceTimeZone: zone),
            "before the fire nothing has fired")
        XCTAssertNil(
            WakeChain.firedOccurrence(
                for: alarm, now: fire.addingTimeInterval(1801), deviceTimeZone: zone),
            "past the bound the window is over")
        XCTAssertNil(
            WakeChain.firedOccurrence(
                for: try makeAlarm(critical: false), now: fire.addingTimeInterval(600),
                deviceTimeZone: zone),
            "standard alarms have no ring window")
    }
}
