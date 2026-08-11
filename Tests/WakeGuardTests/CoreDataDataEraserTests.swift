import Foundation
import XCTest

@testable import WakeGuard

/// WG-250: the production `DataEraser` over real Core Data. A full reset cancels scheduled alarms, clears
/// every store, and revokes the cloud token; deleting optional categories never touches alarms (#9). This
/// is the concrete backing for the compliance gate's `hasProductionEraser`.
final class CoreDataDataEraserTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 500)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeAlarm() throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "America/New_York")))
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule, createdAt: now,
            updatedAt: now)
    }

    private func audit(for alarmID: AlarmID) -> AuditEvent {
        AuditEvent(
            id: AuditEventID(ids.next()), actor: .user, command: .enable(alarmID),
            oldStateHash: nil,
            newStateHash: nil, timestamp: now, source: .userInterface, outcome: .succeeded,
            correlationID: CorrelationID(ids.next()), userVisibleReason: "test")
    }

    func testEraseAllDataClearsEveryStoreCancelsAlarmsAndRevokesToken() async throws {
        let controller = try PersistenceController(inMemory: true)
        let alarms = CoreDataAlarmRepository(controller)
        let auditRepo = CoreDataAuditRepository(controller)
        let adapter = FakeAlarmManagerAdapter()
        let token = InMemoryCloudTokenStore(Sensitive("secret"))
        let alarm = try makeAlarm()
        try await alarms.save(alarm)
        try await auditRepo.append(audit(for: alarm.id))

        let eraser = CoreDataDataEraser(
            persistence: controller, alarms: alarms, alarmManager: adapter, cloudToken: token)
        try await eraser.eraseAllData()

        let remainingAlarms = try await alarms.allAlarms()
        let remainingAudit = try await auditRepo.allEvents()
        XCTAssertTrue(remainingAlarms.isEmpty, "a full reset must clear all alarms")
        XCTAssertTrue(remainingAudit.isEmpty, "a full reset must clear the audit log")
        XCTAssertEqual(
            adapter.cancelledAlarmIDs, [alarm.id], "scheduled alarms are cancelled first")
        let stillHasToken = await token.hasToken()
        XCTAssertFalse(stillHasToken, "the cloud token is revoked on a full reset (#35)")
    }

    func testEraseOptionalSparesAlarms() async throws {
        let controller = try PersistenceController(inMemory: true)
        let alarms = CoreDataAlarmRepository(controller)
        let adapter = FakeAlarmManagerAdapter()
        let alarm = try makeAlarm()
        try await alarms.save(alarm)

        let eraser = CoreDataDataEraser(
            persistence: controller, alarms: alarms, alarmManager: adapter,
            cloudToken: InMemoryCloudTokenStore())
        try await eraser.eraseOptional(Set(OptionalDataCategory.allCases))

        let remaining = try await alarms.allAlarms()
        XCTAssertEqual(
            remaining.map(\.id), [alarm.id], "deleting optional data never touches alarms (#9)")
        XCTAssertTrue(adapter.cancelledAlarmIDs.isEmpty, "optional deletion cancels no alarms")
    }
}
