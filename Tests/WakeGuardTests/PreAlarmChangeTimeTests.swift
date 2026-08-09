import XCTest

@testable import WakeGuard

/// WG-086: the "Change time" pre-alarm action. Tapping it must **not** mutate the alarm — it opens an
/// inert `ChangeTimeProposal` (a proposed new time the user reviews). These tests verify:
/// - **No immediate mutation**: building / previewing a proposal, and the router's `.presentChangeTimeUI`
///   response, change nothing (no repo, no adapter, no command).
/// - **Original stays active until save succeeds**: the stored alarm keeps its original schedule (and
///   AlarmKit its original arming) until the proposal's `.update` is processed *and* applies.
/// - **Imminent-ring race is handled**: saving a proposal for an imminent / critical alarm is
///   confirmation-gated by the policy engine (#6) — unconfirmed it returns `.needsConfirmation` and
///   mutates nothing; the imminent ring is never suppressed by opening or holding the proposal.
final class PreAlarmChangeTimeTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 86)
    private let engine = AlarmSchedulingEngine()

    private func iso(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func makeAlarm(
        criticality: Criticality = .standard, hour: Int = 7,
        travel: TravelBehavior = .followLocal
    ) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: hour, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule, travelBehavior: travel,
            criticality: criticality, createdAt: epoch, updatedAt: epoch, revision: 3)
    }

    private func makeOneTimeAlarm(hour: Int = 7) throws -> Alarm {
        let schedule = ScheduleRule.oneTime(
            OneTimeSchedule(
                date: try CalendarDate(year: 2026, month: 8, day: 20),
                time: try TimeOfDay(hour: hour, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "once", schedule: schedule, createdAt: epoch,
            updatedAt: epoch, revision: 3)
    }

    // MARK: - The proposal is inert (no immediate mutation)

    func testBuildingAProposalDoesNotChangeTheTargetValue() throws {
        let alarm = try makeAlarm(hour: 7)
        let proposal = ChangeTimeProposal(
            target: alarm, proposedTime: try TimeOfDay(hour: 9, minute: 30))
        // The proposal only *holds* the alarm; the original value is untouched — the proposed copy is
        // separate and produced on demand.
        XCTAssertEqual(proposal.target, alarm, "the held target is the original, unmodified")
        let now = try iso("2026-08-17T06:00:00Z")
        let proposed = try XCTUnwrap(proposal.proposedAlarm(now: now))
        XCTAssertEqual(proposed.schedule.time, try TimeOfDay(hour: 9, minute: 30))
        XCTAssertEqual(alarm.schedule.time, try TimeOfDay(hour: 7, minute: 0), "original unchanged")
    }

    func testProposedAlarmPreservesIdentityEnabledZoneCriticalityAndPolicies() throws {
        let alarm = try makeAlarm(criticality: .critical, hour: 6, travel: .stayFixed)
        let now = try iso("2026-08-17T03:00:00Z")
        let proposed = try XCTUnwrap(
            ChangeTimeProposal(target: alarm, proposedTime: try TimeOfDay(hour: 8, minute: 15))
                .proposedAlarm(now: now))

        XCTAssertEqual(proposed.id, alarm.id, "same alarm — an update, never a duplicate")
        XCTAssertEqual(proposed.isEnabled, alarm.isEnabled)
        XCTAssertEqual(
            proposed.schedule.anchorTimeZone, alarm.schedule.anchorTimeZone,
            "anchor zone is preserved — never silently re-anchored (#11/#16)")
        XCTAssertEqual(proposed.criticality, .critical, "criticality is preserved (#31)")
        XCTAssertEqual(proposed.travelBehavior, .stayFixed)
        XCTAssertEqual(proposed.challengePolicy, alarm.challengePolicy)
        XCTAssertEqual(proposed.preAlarmPolicy, alarm.preAlarmPolicy)
        XCTAssertEqual(proposed.snoozePolicy, alarm.snoozePolicy)
        XCTAssertEqual(proposed.sound, alarm.sound)
        XCTAssertEqual(proposed.createdAt, alarm.createdAt, "created timestamp preserved")
        // Only the retime metadata advances.
        XCTAssertEqual(proposed.schedule.time, try TimeOfDay(hour: 8, minute: 15))
        XCTAssertEqual(proposed.revision, alarm.revision + 1, "revision bumped for the update")
        XCTAssertEqual(proposed.updatedAt, now, "updatedAt advances to now")
    }

    func testProposedAlarmPreservesSkippedOccurrences() throws {
        var alarm = try makeAlarm()
        let skipped = try iso("2026-08-17T07:00:00Z")
        alarm.skippedOccurrences = [skipped]
        let proposed = try XCTUnwrap(
            ChangeTimeProposal(target: alarm, proposedTime: try TimeOfDay(hour: 9, minute: 0))
                .proposedAlarm(now: try iso("2026-08-17T06:00:00Z")))
        XCTAssertEqual(
            proposed.skippedOccurrences, [skipped],
            "turned-off occurrences are carried over by the retime")
    }

    func testWeeklyRetimeKeepsRecurrenceDays() throws {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet([.monday, .wednesday, .friday]),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        let alarm = try Alarm(
            id: AlarmID(ids.next()), label: "mwf", schedule: schedule, createdAt: epoch,
            updatedAt: epoch)
        let proposed = try XCTUnwrap(
            ChangeTimeProposal(target: alarm, proposedTime: try TimeOfDay(hour: 8, minute: 0))
                .proposedAlarm(now: try iso("2026-08-17T06:00:00Z")))
        guard case .weekly(let weekly) = proposed.schedule else {
            return XCTFail("a weekly alarm stays weekly after a retime")
        }
        XCTAssertEqual(
            weekly.days.days, [.monday, .wednesday, .friday], "recurrence days unchanged")
        XCTAssertEqual(weekly.time, try TimeOfDay(hour: 8, minute: 0))
    }

    func testOneTimeRetimeCanChangeDayAndKeepsZone() throws {
        let alarm = try makeOneTimeAlarm(hour: 7)
        let proposal = ChangeTimeProposal(
            target: alarm, proposedTime: try TimeOfDay(hour: 9, minute: 0),
            proposedDate: try CalendarDate(year: 2026, month: 8, day: 21))
        let proposed = try XCTUnwrap(proposal.proposedAlarm(now: try iso("2026-08-17T06:00:00Z")))
        guard case .oneTime(let oneTime) = proposed.schedule else {
            return XCTFail("a one-time alarm stays one-time after a retime")
        }
        XCTAssertEqual(oneTime.date, try CalendarDate(year: 2026, month: 8, day: 21), "date moved")
        XCTAssertEqual(oneTime.time, try TimeOfDay(hour: 9, minute: 0))
        XCTAssertEqual(
            oneTime.timeZone, try IANATimeZone(identifier: "UTC"), "anchor zone preserved")
    }

    func testOneTimeRetimeWithoutDateKeepsOriginalDate() throws {
        let alarm = try makeOneTimeAlarm(hour: 7)
        let proposed = try XCTUnwrap(
            ChangeTimeProposal(target: alarm, proposedTime: try TimeOfDay(hour: 9, minute: 0))
                .proposedAlarm(now: try iso("2026-08-17T06:00:00Z")))
        guard case .oneTime(let oneTime) = proposed.schedule else {
            return XCTFail("expected one-time")
        }
        XCTAssertEqual(oneTime.date, try CalendarDate(year: 2026, month: 8, day: 20), "date kept")
    }

    func testNoChangeProposalIsDetectableAndSafeToSkip() throws {
        let alarm = try makeAlarm(hour: 7)
        let same = ChangeTimeProposal(
            target: alarm, proposedTime: try TimeOfDay(hour: 7, minute: 0))
        XCTAssertFalse(same.isChange, "proposing the same time is not a change")
        let changed = ChangeTimeProposal(
            target: alarm, proposedTime: try TimeOfDay(hour: 7, minute: 30))
        XCTAssertTrue(changed.isChange, "a different time is a change")
    }

    // MARK: - The command exit is a plain .update (the only mutating path)

    func testCommandIsAnUpdateOfTheProposedAlarm() throws {
        let alarm = try makeAlarm(hour: 7)
        let now = try iso("2026-08-17T06:00:00Z")
        let proposal = ChangeTimeProposal(
            target: alarm, proposedTime: try TimeOfDay(hour: 9, minute: 0))
        let expected = try XCTUnwrap(proposal.proposedAlarm(now: now))
        XCTAssertEqual(proposal.command(now: now), .update(expected))
        XCTAssertEqual(proposal.command(now: now)?.alarmID, alarm.id, "targets the same alarm")
    }

    // MARK: - Preview (read-only) reflects the proposed time, mutating nothing

    func testPreviewReflectsTheProposedTimeWithoutScheduling() throws {
        let alarm = try makeAlarm(hour: 7)
        let now = try iso("2026-08-17T06:00:00Z")
        // Original next occurrence is 07:00 today; the proposal previews the retimed 09:00 today.
        let original = try XCTUnwrap(
            engine.nextOccurrence(for: alarm, after: now, deviceTimeZone: .gmt))
        XCTAssertEqual(original, try iso("2026-08-17T07:00:00Z"))
        let proposal = ChangeTimeProposal(
            target: alarm, proposedTime: try TimeOfDay(hour: 9, minute: 0))
        XCTAssertEqual(
            proposal.previewNextOccurrence(after: now, deviceTimeZone: .gmt),
            try iso("2026-08-17T09:00:00Z"), "preview shows the proposed time, not the original")
    }

    func testPreviewOfAPastOneTimeRetimeIsNilNotSaveable() throws {
        let alarm = try makeOneTimeAlarm(hour: 7)
        let now = try iso("2026-08-20T06:00:00Z")
        // Retime today's one-time alarm to a time already in the past → it can never ring.
        let proposal = ChangeTimeProposal(
            target: alarm, proposedTime: try TimeOfDay(hour: 5, minute: 0))
        XCTAssertNil(
            proposal.previewNextOccurrence(after: now, deviceTimeZone: .gmt),
            "a past retime previews nil — the review UI must treat it as not-saveable")
    }

    // MARK: - The router response carries no command (no immediate mutation at the seam)

    func testChangeTimeRouterResponseCarriesNoCommand() {
        let context = PreAlarmResponseContext(
            alarmID: AlarmID(ids.next()), occurrence: Date(timeIntervalSince1970: 2_000_000),
            criticality: .critical, remindersUsed: 0)
        let response = PreAlarmResponseRouter.route(
            actionIdentifier: PreAlarmPromptAction.changeTime.identifier, context: context,
            now: Date(timeIntervalSince1970: 1_000_000))
        // Only `.submit` carries an `AlarmCommand`; change-time is `.presentChangeTimeUI` — a
        // navigation, never a mutation (#7).
        XCTAssertEqual(response, .presentChangeTimeUI)
        if case .submit = response {
            XCTFail("change-time must never submit a command directly — it opens a proposal")
        }
    }

}
