import XCTest

@testable import WakeGuard

/// WG-014: the Core Data alarm repository — CRUD, optimistic-revision rejection
/// (typed errors), and that concurrent updates never silently overwrite.
final class CoreDataAlarmRepositoryTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 14)

    private func makeRepository() throws -> CoreDataAlarmRepository {
        CoreDataAlarmRepository(try PersistenceController(inMemory: true))
    }

    private func makeAlarm(revision: Int, label: String = "v0") throws -> Alarm {
        let schedule = ScheduleRule.oneTime(
            OneTimeSchedule(
                date: try CalendarDate(year: 2026, month: 8, day: 15),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: label, schedule: schedule,
            createdAt: epoch, updatedAt: epoch, revision: revision)
    }

    private func assertThrows(
        _ expected: AlarmRepositoryError, _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected) to be thrown")
        } catch let error as AlarmRepositoryError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCRUD() async throws {
        let repo = try makeRepository()
        let empty = try await repo.allAlarms()
        XCTAssertTrue(empty.isEmpty)

        let alarm = try makeAlarm(revision: 0)
        try await repo.save(alarm)
        let fetched = try await repo.alarm(id: alarm.id)
        XCTAssertEqual(fetched, alarm)
        let all = try await repo.allAlarms()
        XCTAssertEqual(all.count, 1)

        var updated = alarm
        updated.revision = 1
        updated.label = "renamed"
        try await repo.save(updated)
        let reFetched = try await repo.alarm(id: alarm.id)
        XCTAssertEqual(reFetched?.label, "renamed")
        XCTAssertEqual(reFetched?.revision, 1)

        try await repo.deleteAlarm(id: alarm.id)
        let afterDelete = try await repo.alarm(id: alarm.id)
        XCTAssertNil(afterDelete)
    }

    func testStaleRevisionSaveIsRejectedAndDoesNotOverwrite() async throws {
        let repo = try makeRepository()
        let base = try makeAlarm(revision: 0)
        try await repo.save(base)

        var current = base
        current.revision = 1
        current.label = "current"
        try await repo.save(current)  // rev 1 > 0 -> applied

        // A save whose revision (1) is not newer than the stored (1) is rejected.
        var stale = base
        stale.revision = 1
        stale.label = "stale"
        await assertThrows(.staleRevision(stored: 1, incoming: 1)) {
            try await repo.save(stale)
        }

        // An even-older revision is rejected too.
        var older = base
        older.revision = 0
        older.label = "older"
        await assertThrows(.staleRevision(stored: 1, incoming: 0)) {
            try await repo.save(older)
        }

        // The stored alarm is unchanged (the rejected saves did not overwrite it).
        let loaded = try await repo.alarm(id: base.id)
        XCTAssertEqual(loaded?.label, "current")
        XCTAssertEqual(loaded?.revision, 1)
    }

    func testNewAlarmInsertsWithoutConflict() async throws {
        let repo = try makeRepository()
        let alarm = try makeAlarm(revision: 0)
        try await repo.save(alarm)
        let loaded = try await repo.alarm(id: alarm.id)
        XCTAssertEqual(loaded, alarm)
    }

    /// Classifies each concurrent write: it must either win or be rejected with a
    /// *typed* `AlarmRepositoryError` — never leak a raw error, never silently win.
    private enum WriteOutcome: Sendable {
        case won
        case rejected
        case leaked
    }

    func testConcurrentUpdatesDoNotSilentlyOverwrite() async throws {
        let repo = try makeRepository()
        let base = try makeAlarm(revision: 0)
        try await repo.save(base)

        // Eight concurrent edits all based on rev 0, each bumping to rev 1. Under
        // contention the losers hit either the app-level guard (.staleRevision) or
        // the store-level merge policy (.conflict) — both are typed.
        let outcomes = await withTaskGroup(of: WriteOutcome.self) { group in
            for label in ["A", "B", "C", "D", "E", "F", "G", "H"] {
                group.addTask {
                    var edit = base
                    edit.revision = 1
                    edit.label = label
                    do {
                        try await repo.save(edit)
                        return .won
                    } catch is AlarmRepositoryError {
                        return .rejected
                    } catch {
                        return .leaked
                    }
                }
            }
            var results: [WriteOutcome] = []
            for await outcome in group {
                results.append(outcome)
            }
            return results
        }

        XCTAssertEqual(
            outcomes.filter { $0 == .won }.count, 1,
            "exactly one rev-1 update applies — no silent overwrite (#10)")
        XCTAssertEqual(
            outcomes.filter { $0 == .leaked }.count, 0,
            "every rejection is a typed AlarmRepositoryError, not a raw NSError")
        let loaded = try await repo.alarm(id: base.id)
        XCTAssertEqual(loaded?.revision, 1)
    }
}
