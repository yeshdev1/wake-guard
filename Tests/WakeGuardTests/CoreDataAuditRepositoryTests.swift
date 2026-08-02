import CoreData
import XCTest

@testable import WakeGuard

/// WG-015: the Core Data append-only audit repository. Covers query-by-alarm and
/// all-events history (#49), deterministic ordering, that a recorded event can
/// never be updated through the port (#48), that #41's enumerated sensitive
/// categories stay out of the payload while state is hashed, resilience to a single
/// undecodable row, and idempotent/lossless behavior under concurrent appends.
///
/// The `AuditRepository` port (WG-012) intentionally exposes *no* update or delete
/// — append-only by shape. These tests therefore prove immutability behaviorally:
/// re-appending an id cannot overwrite the stored record.
final class CoreDataAuditRepositoryTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 15)

    private func makeController() throws -> PersistenceController {
        try PersistenceController(inMemory: true)
    }

    private func makeRepository(_ controller: PersistenceController) -> CoreDataAuditRepository {
        CoreDataAuditRepository(controller)
    }

    private func makeEvent(
        id: AuditEventID? = nil,
        alarmID: AlarmID,
        timestamp: Date,
        oldStateHash: String? = "old",
        newStateHash: String? = "new",
        reason: String = "test"
    ) -> AuditEvent {
        AuditEvent(
            id: id ?? AuditEventID(ids.next()),
            actor: .user,
            command: .snooze(alarmID),
            oldStateHash: oldStateHash,
            newStateHash: newStateHash,
            timestamp: timestamp,
            source: .userInterface,
            outcome: .succeeded,
            correlationID: CorrelationID(ids.next()),
            userVisibleReason: reason)
    }

    private func makeAlarm(label: String) throws -> Alarm {
        let schedule = ScheduleRule.oneTime(
            OneTimeSchedule(
                date: try CalendarDate(year: 2026, month: 8, day: 15),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: label, schedule: schedule,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    /// Reads the raw persisted `payload` blobs directly from the store (same
    /// controller, a fresh context) — used to assert exactly what bytes the audit
    /// wrote, independent of the decode path.
    private func rawPayloads(_ controller: PersistenceController) async throws -> [Data] {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "AuditRecord")
            return try context.fetch(request).compactMap {
                $0.value(forKey: "payload") as? Data
            }
        }
    }

    /// Inserts an `AuditRecord` row with an arbitrary (possibly corrupt) payload,
    /// bypassing the repository — simulates a future-schema or bit-rotted row.
    private func insertRawAudit(
        _ controller: PersistenceController, id: AuditEventID, alarmID: AlarmID,
        timestamp: Date, payload: Data
    ) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            guard
                let entity = NSEntityDescription.entity(
                    forEntityName: "AuditRecord", in: context)
            else {
                return XCTFail("AuditRecord entity missing")
            }
            let record = NSManagedObject(entity: entity, insertInto: context)
            record.setValue(id.rawValue.uuidString, forKey: "id")
            record.setValue(alarmID.rawValue.uuidString, forKey: "alarmID")
            record.setValue(timestamp, forKey: "timestamp")
            record.setValue(payload, forKey: "payload")
            try context.save()
        }
    }

    func testEventsForAlarmReturnsOnlyThatAlarmChronologically() async throws {
        let repo = makeRepository(try makeController())
        let alarmA = AlarmID(ids.next())
        let alarmB = AlarmID(ids.next())
        // Append interleaved and out of timestamp order.
        try await repo.append(
            makeEvent(alarmID: alarmA, timestamp: Date(timeIntervalSince1970: 200), reason: "a2"))
        try await repo.append(
            makeEvent(alarmID: alarmB, timestamp: Date(timeIntervalSince1970: 150), reason: "b1"))
        try await repo.append(
            makeEvent(alarmID: alarmA, timestamp: Date(timeIntervalSince1970: 100), reason: "a1"))

        let aHistory = try await repo.events(forAlarm: alarmA)
        XCTAssertEqual(aHistory.map(\.userVisibleReason), ["a1", "a2"])
        let bHistory = try await repo.events(forAlarm: alarmB)
        XCTAssertEqual(bHistory.map(\.userVisibleReason), ["b1"])
    }

    func testAllEventsOrderedByTimestampThenId() async throws {
        let repo = makeRepository(try makeController())
        let alarmID = AlarmID(ids.next())
        let sameInstant = Date(timeIntervalSince1970: 500)
        let later = makeEvent(
            alarmID: alarmID, timestamp: Date(timeIntervalSince1970: 900), reason: "later")
        let tieA = makeEvent(alarmID: alarmID, timestamp: sameInstant, reason: "tieA")
        let tieB = makeEvent(alarmID: alarmID, timestamp: sameInstant, reason: "tieB")
        let earlier = makeEvent(
            alarmID: alarmID, timestamp: Date(timeIntervalSince1970: 100), reason: "earlier")
        // Append scrambled.
        for event in [later, tieB, earlier, tieA] {
            try await repo.append(event)
        }

        // Equal-instant events break the tie by id ascending — a stable, deterministic
        // order regardless of append order.
        let expectedTie =
            [tieA, tieB]
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
            .map(\.userVisibleReason)
        let all = try await repo.allEvents()
        XCTAssertEqual(all.map(\.userVisibleReason), ["earlier"] + expectedTie + ["later"])
    }

    func testAppendIsIdempotentAndCannotUpdatePastRecord() async throws {
        let repo = makeRepository(try makeController())
        let alarmID = AlarmID(ids.next())
        let eventID = AuditEventID(ids.next())
        let original = makeEvent(
            id: eventID, alarmID: alarmID, timestamp: Date(timeIntervalSince1970: 100),
            newStateHash: "original", reason: "original")
        try await repo.append(original)

        // Re-append the same id carrying mutated content. An append-only store must
        // not let this overwrite the recorded event (#48) nor add a second row.
        let tampered = makeEvent(
            id: eventID, alarmID: alarmID, timestamp: Date(timeIntervalSince1970: 999),
            newStateHash: "tampered", reason: "tampered")
        try await repo.append(tampered)

        let all = try await repo.allEvents()
        XCTAssertEqual(all.count, 1, "re-appending an existing id must not add a row")
        XCTAssertEqual(all.first, original, "the recorded event is immutable")
        XCTAssertEqual(all.first?.newStateHash, "original")
        XCTAssertEqual(all.first?.userVisibleReason, "original")
    }

    func testAuditExcludesEnumeratedSensitiveCategoriesAndHashesState() async throws {
        let controller = try makeController()
        let repo = makeRepository(controller)
        // `.create` embeds the full Alarm — the widest payload — including its
        // free-text `label`. Use a label a naive sensitive-content scan would flag.
        let alarm = try makeAlarm(label: "take insulin 20u")
        let event = AuditEvent(
            id: AuditEventID(ids.next()),
            actor: .user,
            command: .create(alarm),
            oldStateHash: nil,
            newStateHash: "sha256:1111BBBB",
            timestamp: Date(timeIntervalSince1970: 100),
            source: .userInterface,
            outcome: .succeeded,
            correlationID: CorrelationID(ids.next()),
            userVisibleReason: "created alarm")
        try await repo.append(event)

        let payloads = try await rawPayloads(controller)
        XCTAssertEqual(payloads.count, 1)
        guard let text = String(bytes: payloads[0], encoding: .utf8) else {
            return XCTFail("audit payload was not valid UTF-8")
        }
        // State deltas are recorded as hashes, never raw pre-images.
        XCTAssertTrue(text.contains("sha256:1111BBBB"), "state is persisted as a hash")
        // #41's ENUMERATED categories are excluded by construction: no health sample,
        // precise coordinate, calendar title, journal text, or LLM-prompt field exists
        // anywhere in the AuditEvent/AlarmCommand/Alarm graph, so none can appear —
        // even on this widest `.create` payload.
        XCTAssertFalse(text.contains("heart_rate_bpm"))
        XCTAssertFalse(text.contains("journalText"))
        XCTAssertFalse(text.contains("latitude"))
        // HONEST record of today's design (an earlier `.snooze` test was a strawman):
        // the command is stored in full, so a free-text alarm label DOES land in the
        // append-only trail. Accepted for MVP — on-device, file-protected, never
        // transmitted — with a label-redaction boundary deferred to the command
        // processor (DECISIONS WG-015, tracking #42/#43).
        XCTAssertTrue(
            text.contains("take insulin 20u"),
            "documents that the raw command (incl. label) is stored today")
    }

    func testUndecodableRowIsSkippedNotFatalToQueries() async throws {
        let controller = try makeController()
        let repo = makeRepository(controller)
        let alarmID = AlarmID(ids.next())
        try await repo.append(
            makeEvent(
                alarmID: alarmID, timestamp: Date(timeIntervalSince1970: 100), reason: "good"))

        // A garbled payload (not valid AuditEvent JSON) lands in the store.
        try await insertRawAudit(
            controller, id: AuditEventID(ids.next()), alarmID: alarmID,
            timestamp: Date(timeIntervalSince1970: 200), payload: Data("not-json".utf8))

        // One poison row must not blind the whole trail (#49): the good event still
        // returns from both query paths rather than the query throwing.
        let all = try await repo.allEvents()
        XCTAssertEqual(all.map(\.userVisibleReason), ["good"])
        let history = try await repo.events(forAlarm: alarmID)
        XCTAssertEqual(history.map(\.userVisibleReason), ["good"])
    }

    func testConcurrentAppendOfSameEventYieldsSingleRow() async throws {
        let repo = makeRepository(try makeController())
        let alarmID = AlarmID(ids.next())
        let event = makeEvent(alarmID: alarmID, timestamp: Date(timeIntervalSince1970: 100))

        // Eight racing appends of the same event. The store-level uniqueness conflict
        // must be absorbed as an idempotent no-op, never surfaced or duplicated.
        let anyThrew = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    do {
                        try await repo.append(event)
                        return false
                    } catch {
                        return true
                    }
                }
            }
            var threw = false
            for await didThrow in group where didThrow { threw = true }
            return threw
        }

        XCTAssertFalse(anyThrew, "a concurrent duplicate append is absorbed, not thrown")
        let all = try await repo.allEvents()
        XCTAssertEqual(all.count, 1, "the same event id persists exactly once (#48)")
    }

    func testConcurrentAppendOfDistinctEventsAllPersist() async throws {
        let repo = makeRepository(try makeController())
        let alarmID = AlarmID(ids.next())
        // Build all events (and thus consume the id generator) before racing, so the
        // concurrency is only in the appends.
        let events = (0..<8).map { index in
            makeEvent(
                alarmID: alarmID, timestamp: Date(timeIntervalSince1970: Double(index)),
                reason: "e\(index)")
        }

        let anyThrew = await withTaskGroup(of: Bool.self) { group in
            for event in events {
                group.addTask {
                    do {
                        try await repo.append(event)
                        return false
                    } catch {
                        return true
                    }
                }
            }
            var threw = false
            for await didThrow in group where didThrow { threw = true }
            return threw
        }

        XCTAssertFalse(anyThrew, "distinct-id appends never conflict")
        let all = try await repo.allEvents()
        XCTAssertEqual(all.count, 8, "no concurrent append is lost")
        XCTAssertEqual(Set(all.map(\.id)), Set(events.map(\.id)))
    }
}
