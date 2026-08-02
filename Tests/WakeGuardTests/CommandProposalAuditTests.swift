import Foundation
import XCTest

@testable import WakeGuard

/// WG-011: command / proposal / audit models — their separation, Codable
/// round-tripping, proposal expiry, and fail-safe rejection of unknown
/// actor/source/outcome values.
final class CommandProposalAuditTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 11)

    private func makeAlarm() throws -> Alarm {
        let timeZone = try IANATimeZone(identifier: "UTC")
        let schedule = ScheduleRule.oneTime(
            OneTimeSchedule(
                date: try CalendarDate(year: 2026, month: 8, day: 15),
                time: try TimeOfDay(hour: 6, minute: 30),
                timeZone: timeZone))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "Test", schedule: schedule,
            createdAt: epoch, updatedAt: epoch)
    }

    private func makeProposal(command: AlarmCommand, expiresAt: Date) -> AlarmProposal {
        AlarmProposal(
            proposedCommand: command,
            explanation: "You appear awake.",
            evidenceReferences: [EvidenceReference(kind: .motionHistory, reference: "trace-1")],
            confidence: .medium,
            expiresAt: expiresAt,
            provider: ModelProviderMetadata(
                providerName: "apple.foundation", modelIdentifier: "on-device", isOnDevice: true))
    }

    private func makeAuditEvent(actor: AuditActor, source: CommandSource) throws -> AuditEvent {
        AuditEvent(
            id: AuditEventID(ids.next()),
            actor: actor,
            command: AlarmCommand.recover(try makeAlarm().id),
            oldStateHash: "old",
            newStateHash: "new",
            timestamp: Date(timeIntervalSince1970: 42),
            source: source,
            outcome: .succeeded,
            correlationID: CorrelationID(ids.next()),
            userVisibleReason: "Recovered after restart")
    }

    // MARK: command vs proposal are separate types

    func testProposalOnlyCarriesACommandAndIsDistinct() throws {
        let command = AlarmCommand.disable(try makeAlarm().id)
        let proposal = makeProposal(command: command, expiresAt: Date(timeIntervalSince1970: 100))
        // The proposal merely *carries* the command; it is a distinct type with no
        // execution surface. Acting on it still requires the policy engine (WG-028).
        XCTAssertEqual(proposal.proposedCommand, command)
        XCTAssertFalse(proposal.isExpired(at: Date(timeIntervalSince1970: 0)))
    }

    func testAlarmCommandAlarmIDAccessor() throws {
        let alarm = try makeAlarm()
        let fire = Date(timeIntervalSince1970: 10)
        XCTAssertEqual(AlarmCommand.create(alarm).alarmID, alarm.id)
        XCTAssertEqual(AlarmCommand.enable(alarm.id).alarmID, alarm.id)
        XCTAssertEqual(AlarmCommand.cancelOccurrence(alarm.id, fireTime: fire).alarmID, alarm.id)
        XCTAssertEqual(
            AlarmCommand.rescheduleOccurrence(alarm.id, fireTime: fire, to: fire).alarmID, alarm.id)
    }

    // MARK: Codable round-trips

    func testAlarmCommandCodableRoundTrips() throws {
        let command = AlarmCommand.snooze(try makeAlarm().id)
        let decoded = try JSONDecoder().decode(
            AlarmCommand.self, from: try JSONEncoder().encode(command))
        XCTAssertEqual(command, decoded)
    }

    func testAlarmProposalCodableRoundTripsAndExpires() throws {
        let command = AlarmCommand.enable(try makeAlarm().id)
        let proposal = makeProposal(command: command, expiresAt: Date(timeIntervalSince1970: 500))
        let decoded = try JSONDecoder().decode(
            AlarmProposal.self, from: try JSONEncoder().encode(proposal))
        XCTAssertEqual(proposal, decoded)

        let clock = TestClock(now: Date(timeIntervalSince1970: 499))
        XCTAssertFalse(decoded.isExpired(at: clock.now))
        clock.advance(by: 2)
        XCTAssertTrue(decoded.isExpired(at: clock.now))
    }

    // MARK: audit event

    func testAuditEventCapturesRequiredFieldsAndFlagsRecovery() throws {
        let event = try makeAuditEvent(actor: .recovery, source: .recovery)
        XCTAssertEqual(event.actor, .recovery)
        XCTAssertEqual(event.oldStateHash, "old")
        XCTAssertEqual(event.newStateHash, "new")
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.userVisibleReason, "Recovered after restart")
        XCTAssertTrue(event.isRecovery)

        let edit = try makeAuditEvent(actor: .user, source: .userInterface)
        XCTAssertFalse(edit.isRecovery)
    }

    func testAuditEventCodableRoundTrips() throws {
        let event = try makeAuditEvent(actor: .user, source: .userInterface)
        let decoded = try JSONDecoder().decode(
            AuditEvent.self, from: try JSONEncoder().encode(event))
        XCTAssertEqual(event, decoded)
    }

    // MARK: unknown actor/source/outcome fail safely (#27)

    func testUnknownEnumeratedValuesFailToDecode() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(AuditActor.self, from: Data("\"hacker\"".utf8)))
        XCTAssertThrowsError(
            try JSONDecoder().decode(CommandSource.self, from: Data("\"bogus\"".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(Outcome.self, from: Data("\"weird\"".utf8)))
        XCTAssertThrowsError(
            try JSONDecoder().decode(ConfidenceBand.self, from: Data("\"certain\"".utf8)))
        XCTAssertThrowsError(
            try JSONDecoder().decode(EvidenceKind.self, from: Data("\"telepathy\"".utf8)))
        XCTAssertEqual(
            try JSONDecoder().decode(AuditActor.self, from: Data("\"recovery\"".utf8)), .recovery)
    }

    func testAuditEventWithUnknownActorFailsToDecode() throws {
        let event = try makeAuditEvent(actor: .user, source: .userInterface)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        object["actor"] = "intruder"
        let tampered = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(AuditEvent.self, from: tampered))
    }
}
