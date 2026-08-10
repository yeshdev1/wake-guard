import Foundation
import XCTest

@testable import WakeGuard

/// WG-227: persistence corruption & recovery. Verifies **recoverable data is preserved** (a readable
/// desired state is re-scheduled on reconcile), that **unsafe ambiguity keeps alarms scheduled** (when the
/// desired state can't be read, reconciliation repairs nothing — it never cancels a system alarm), and that
/// **recovery is audited**.
final class CorruptionRecoveryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let ids = DeterministicIDGenerator(seed: 27)

    private func makeProcessor(
        alarms: any AlarmRepository, adapter: FakeAlarmManagerAdapter
    ) throws -> (AlarmCommandProcessor, CoreDataAuditRepository) {
        let controller = try PersistenceController(inMemory: true)
        let audit = CoreDataAuditRepository(controller)
        let processor = AlarmCommandProcessor(
            policy: FakeAlarmPolicyEngine(), alarms: alarms, audit: audit,
            outbox: CoreDataOutboxRepository(controller), alarmManager: adapter,
            clock: TestClock(now: now), ids: DeterministicIDGenerator(seed: 5),
            deviceTimeZone: { .gmt })
        return (processor, audit)
    }

    private func makeAlarm() throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", isEnabled: true, schedule: schedule,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    // MARK: unsafe ambiguity keeps alarms scheduled

    func testUnreadableDesiredStateNeverCancelsAScheduledAlarm() async throws {
        // A critical alarm is live in the system, but the desired state (store) is corrupt / unreadable.
        let adapter = FakeAlarmManagerAdapter()
        let live = ScheduledAlarmSnapshot(
            alarmID: AlarmID(ids.next()), fireTime: now.addingTimeInterval(3600), isCritical: true)
        adapter.setScheduled([live])
        let (processor, _) = try makeProcessor(alarms: FailingAlarmRepository(), adapter: adapter)

        let summary = await processor.reconcile()

        XCTAssertTrue(
            adapter.cancelledAlarmIDs.isEmpty,
            "reconciliation must not cancel a live alarm when the desired state is unreadable (#10)"
        )
        XCTAssertEqual(adapter.currentlyScheduled.count, 1, "the alarm stays scheduled — fail safe")
        XCTAssertTrue(summary.skipped, "an unreadable state skips reconciliation (repairs nothing)")
    }

    // MARK: recoverable data is preserved + recovery is audited

    func testReadableDesiredStateIsReconciledAndAudited() async throws {
        let adapter = FakeAlarmManagerAdapter()
        let alarms = try {
            let controller = try PersistenceController(inMemory: true)
            return CoreDataAlarmRepository(controller)
        }()
        let (processor, audit) = try makeProcessor(alarms: alarms, adapter: adapter)

        // Recoverable data exists in the store, but the system has lost the schedule (e.g. after a crash).
        let alarm = try makeAlarm()
        try await alarms.save(alarm)

        let summary = await processor.reconcile()

        XCTAssertEqual(
            summary, ReconciliationSummary(scheduled: 1), "recoverable data is re-scheduled")
        XCTAssertEqual(adapter.currentlyScheduled.count, 1)
        let events = try await audit.allEvents()
        XCTAssertTrue(
            events.contains { $0.actor == .systemReconciliation },
            "recovery must be audited as a reconciliation action")
    }
}

/// A repository whose reads always throw — simulates a corrupt/unreadable desired state.
private struct FailingAlarmRepository: AlarmRepository {
    func save(_ alarm: Alarm) async throws { throw AlarmRepositoryError.storageUnavailable }
    func alarm(id: AlarmID) async throws -> Alarm? { throw AlarmRepositoryError.storageUnavailable }
    func allAlarms() async throws -> [Alarm] { throw AlarmRepositoryError.storageUnavailable }
    func deleteAlarm(id: AlarmID) async throws { throw AlarmRepositoryError.storageUnavailable }
}
