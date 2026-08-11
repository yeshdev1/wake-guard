import Foundation
import XCTest

@testable import WakeGuard

/// WG-250/182: the production retention job. It prunes audit rows past their window via `RetentionCleanup`,
/// bounded by the 365-day critical-audit floor (#48) — a safety-relevant change to a critical alarm is
/// never purged early. This is the concrete backing for the compliance gate's `hasRetentionCaller`.
final class RetentionCleanupJobTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 600)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeAlarm(critical: Bool) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "America/New_York")))
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule,
            criticality: critical ? .critical : .standard, createdAt: now, updatedAt: now)
    }

    private func audit(for alarmID: AlarmID, daysAgo: Double) -> AuditEvent {
        AuditEvent(
            id: AuditEventID(ids.next()), actor: .user, command: .enable(alarmID),
            oldStateHash: nil,
            newStateHash: nil, timestamp: now.addingTimeInterval(-daysAgo * 86_400),
            source: .userInterface, outcome: .succeeded, correlationID: CorrelationID(ids.next()),
            userVisibleReason: "x")
    }

    func testExpiredNonCriticalAuditPrunedCriticalWithinFloorRetained() async throws {
        let controller = try PersistenceController(inMemory: true)
        let alarms = CoreDataAlarmRepository(controller)
        let auditRepo = CoreDataAuditRepository(controller)
        let standardAlarm = try makeAlarm(critical: false)
        let criticalAlarm = try makeAlarm(critical: true)
        try await alarms.save(standardAlarm)
        try await alarms.save(criticalAlarm)

        let expiredStandard = audit(for: standardAlarm.id, daysAgo: 200)  // > 180-day audit window
        let recentStandard = audit(for: standardAlarm.id, daysAgo: 10)  // fresh → kept
        let oldCritical = audit(for: criticalAlarm.id, daysAgo: 200)  // < 365-day floor → kept
        for event in [expiredStandard, recentStandard, oldCritical] {
            try await auditRepo.append(event)
        }

        let job = RetentionCleanupJob(
            persistence: controller, audit: auditRepo, alarms: alarms, clock: TestClock(now: now))
        await job.run()

        let remaining = Set(try await auditRepo.allEvents().map(\.id))
        XCTAssertFalse(
            remaining.contains(expiredStandard.id), "an expired non-critical audit row is pruned")
        XCTAssertTrue(remaining.contains(recentStandard.id), "a fresh audit row is kept")
        XCTAssertTrue(
            remaining.contains(oldCritical.id),
            "a critical-alarm audit row within the 365-day floor is kept (#48)")
    }
}
