import Foundation
import XCTest

@testable import WakeGuard

/// WG-226: alarm command concurrency stress. Hammers the `AlarmCommandProcessor` (the single
/// command-serialization boundary, #2) with **simultaneous** create/reconcile events and verifies they
/// **serialize safely** (no crash / data race), that there is **no lost update** (every applied create
/// persists), and that **idempotency holds** (re-creating the same alarm doesn't duplicate it).
final class AlarmCommandConcurrencyTests: XCTestCase {

    private func makeProcessor() throws -> (AlarmCommandProcessor, CoreDataAlarmRepository) {
        let controller = try PersistenceController(inMemory: true)
        let alarms = CoreDataAlarmRepository(controller)
        let processor = AlarmCommandProcessor(
            policy: FakeAlarmPolicyEngine(decision: .authorized), alarms: alarms,
            audit: CoreDataAuditRepository(controller),
            outbox: CoreDataOutboxRepository(controller),
            alarmManager: FakeAlarmManagerAdapter(),
            clock: TestClock(now: Date(timeIntervalSince1970: 1_000_000)),
            ids: DeterministicIDGenerator(seed: 27), deviceTimeZone: { .gmt })
        return (processor, alarms)
    }

    private func makeAlarm(id: UUID) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(id), label: "wake", isEnabled: true, schedule: schedule, createdAt: epoch,
            updatedAt: epoch, revision: 0)
    }

    func testSimultaneousCreatesAndReconcilesSerializeWithoutLostUpdate() async throws {
        let (processor, alarms) = try makeProcessor()
        let ids = (0..<50).map { _ in UUID() }
        // Build the alarms up front so the sending task closures capture only Sendable values (no `self`).
        let fixtures = try ids.map { try makeAlarm(id: $0) }

        await withTaskGroup(of: Void.self) { group in
            for alarm in fixtures {
                group.addTask {
                    _ = await processor.process(.create(alarm), from: .userInterface, by: .user)
                }
                // Interleave reconciliation events with the edits.
                group.addTask { _ = await processor.reconcile() }
            }
        }

        // No lost update: every distinct create persisted.
        for id in ids {
            let stored = try await alarms.alarm(id: AlarmID(id))
            XCTAssertNotNil(stored, "a concurrent create was lost")
        }
    }

    func testDuplicateConcurrentCreateIsIdempotent() async throws {
        let (processor, alarms) = try makeProcessor()
        let id = UUID()
        let alarm = try makeAlarm(id: id)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    _ = await processor.process(.create(alarm), from: .userInterface, by: .user)
                }
            }
        }

        // The alarm exists exactly once — concurrent duplicates don't corrupt or multiply it.
        let stored = try await alarms.alarm(id: AlarmID(id))
        XCTAssertNotNil(stored)
        let all = try await alarms.allAlarms()
        XCTAssertEqual(
            all.filter { $0.id == AlarmID(id) }.count, 1, "duplicate creates must be idempotent")
    }
}
