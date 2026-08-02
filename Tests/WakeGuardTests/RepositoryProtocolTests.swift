import Foundation
import XCTest

@testable import WakeGuard

/// WG-012: the persistence-port protocols are coherent and usable. Each is
/// exercised through a minimal in-test actor fake; the real implementations are
/// WG-013–016. Also pins the append-only shape and fail-closed decoding.
final class RepositoryProtocolTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 12)

    // MARK: fixtures

    private func makeAlarm() throws -> Alarm {
        let schedule = ScheduleRule.oneTime(
            OneTimeSchedule(
                date: try CalendarDate(year: 2026, month: 8, day: 15),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "T", schedule: schedule,
            createdAt: epoch, updatedAt: epoch)
    }

    private func makeAuditEvent(alarmID: AlarmID) -> AuditEvent {
        AuditEvent(
            id: AuditEventID(ids.next()), actor: .user, command: .enable(alarmID),
            oldStateHash: nil, newStateHash: "new", timestamp: Date(timeIntervalSince1970: 1),
            source: .userInterface, outcome: .succeeded, correlationID: CorrelationID(ids.next()),
            userVisibleReason: "Enabled")
    }

    private func makeOutboxEntry() throws -> OutboxEntry {
        OutboxEntry(
            id: OutboxEntryID(ids.next()), command: .enable(try makeAlarm().id),
            idempotencyKey: "key-1", status: .pending, createdAt: Date(timeIntervalSince1970: 0),
            attempts: 0, lastFailureReason: nil)
    }

    // MARK: fakes (implementations are WG-014/015/016)

    private actor FakeAlarmRepository: AlarmRepository {
        private var storage: [AlarmID: Alarm] = [:]
        func save(_ alarm: Alarm) async throws { storage[alarm.id] = alarm }
        func alarm(id: AlarmID) async throws -> Alarm? { storage[id] }
        func allAlarms() async throws -> [Alarm] { Array(storage.values) }
        func deleteAlarm(id: AlarmID) async throws { storage[id] = nil }
    }

    private actor FakeAuditRepository: AuditRepository {
        private var storage: [AuditEvent] = []
        func append(_ event: AuditEvent) async throws { storage.append(event) }
        func events(forAlarm id: AlarmID) async throws -> [AuditEvent] {
            storage.filter { $0.alarmID == id }
        }
        func allEvents() async throws -> [AuditEvent] { storage }
    }

    private actor FakeSettingsRepository: SettingsRepository {
        private var stored: AppSettings?
        func settings() async throws -> AppSettings { stored ?? .default }
        func save(_ settings: AppSettings) async throws { stored = settings }
    }

    private actor FakeOutboxRepository: OutboxRepository {
        private var entries: [OutboxEntryID: OutboxEntry] = [:]
        func enqueue(_ entry: OutboxEntry) async throws { entries[entry.id] = entry }
        func entry(id: OutboxEntryID) async throws -> OutboxEntry? { entries[id] }
        func entry(idempotencyKey: String) async throws -> OutboxEntry? {
            entries.values.first { $0.idempotencyKey == idempotencyKey }
        }
        func pendingEntries() async throws -> [OutboxEntry] {
            entries.values.filter { $0.status == .pending }
        }
        func unresolvedEntries() async throws -> [OutboxEntry] {
            entries.values.filter { !$0.status.isTerminal }
        }
        func markInProgress(_ id: OutboxEntryID) async throws { entries[id]?.status = .inProgress }
        func markApplied(_ id: OutboxEntryID) async throws { entries[id]?.status = .applied }
        func markUncertain(_ id: OutboxEntryID) async throws { entries[id]?.status = .uncertain }
        func markFailed(_ id: OutboxEntryID, reason: String) async throws {
            entries[id]?.status = .failed
            entries[id]?.lastFailureReason = reason
            entries[id]?.attempts += 1
        }
    }

    // MARK: exercises

    func testAlarmRepositorySaveFetchDelete() async throws {
        let repo = FakeAlarmRepository()
        let alarm = try makeAlarm()
        try await repo.save(alarm)
        let fetched = try await repo.alarm(id: alarm.id)
        XCTAssertEqual(fetched, alarm)
        let all = try await repo.allAlarms()
        XCTAssertEqual(all.count, 1)
        try await repo.deleteAlarm(id: alarm.id)
        let afterDelete = try await repo.alarm(id: alarm.id)
        XCTAssertNil(afterDelete)
    }

    func testAuditRepositoryAppendsAndQueriesByAlarm() async throws {
        // The protocol exposes no update/delete — append-only by construction (#48).
        let repo = FakeAuditRepository()
        let alarm = try makeAlarm()
        try await repo.append(makeAuditEvent(alarmID: alarm.id))
        try await repo.append(makeAuditEvent(alarmID: alarm.id))
        let forAlarm = try await repo.events(forAlarm: alarm.id)
        XCTAssertEqual(forAlarm.count, 2)
        let all = try await repo.allEvents()
        XCTAssertEqual(all.count, 2)
    }

    func testSettingsRepositoryReturnsDefaultThenPersists() async throws {
        let repo = FakeSettingsRepository()
        let initial = try await repo.settings()
        XCTAssertEqual(initial, .default)
        var updated = AppSettings.default
        updated.preAlarmPromptEnabled = true
        try await repo.save(updated)
        let saved = try await repo.settings()
        XCTAssertEqual(saved, updated)
    }

    func testOutboxRepositoryLifecycle() async throws {
        let repo = FakeOutboxRepository()
        let entry = try makeOutboxEntry()
        try await repo.enqueue(entry)

        let pending = try await repo.pendingEntries()
        XCTAssertEqual(pending.map(\.id), [entry.id])
        let byKey = try await repo.entry(idempotencyKey: entry.idempotencyKey)
        XCTAssertEqual(byKey?.id, entry.id)

        try await repo.markInProgress(entry.id)
        let pendingAfter = try await repo.pendingEntries()
        XCTAssertTrue(pendingAfter.isEmpty)
        let unresolvedInProgress = try await repo.unresolvedEntries()
        XCTAssertEqual(
            unresolvedInProgress.map(\.id), [entry.id],
            "an in-progress entry is still unresolved — reconciliation recovers it (#10)")

        try await repo.markUncertain(entry.id)
        let uncertain = try await repo.entry(id: entry.id)
        XCTAssertEqual(uncertain?.status, .uncertain)
        let unresolvedUncertain = try await repo.unresolvedEntries()
        XCTAssertFalse(unresolvedUncertain.isEmpty, "uncertain is non-terminal")

        try await repo.markFailed(entry.id, reason: "AlarmKit denied")
        let failed = try await repo.entry(id: entry.id)
        XCTAssertEqual(failed?.status, .failed)
        XCTAssertEqual(failed?.lastFailureReason, "AlarmKit denied")
        XCTAssertEqual(failed?.attempts, 1)

        try await repo.markApplied(entry.id)
        let applied = try await repo.entry(id: entry.id)
        XCTAssertEqual(applied?.status, .applied)
        let unresolvedApplied = try await repo.unresolvedEntries()
        XCTAssertTrue(unresolvedApplied.isEmpty, "applied is terminal")
    }

    // MARK: model soundness

    func testOutboxStatusFailsClosedOnUnknownValue() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(OutboxStatus.self, from: Data("\"exploded\"".utf8)))
    }

    func testSettingsAndOutboxEntryCodableRoundTrip() throws {
        let settings = AppSettings.default
        XCTAssertEqual(
            try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings)),
            settings)
        let entry = try makeOutboxEntry()
        XCTAssertEqual(
            try JSONDecoder().decode(OutboxEntry.self, from: try JSONEncoder().encode(entry)),
            entry)
    }
}
