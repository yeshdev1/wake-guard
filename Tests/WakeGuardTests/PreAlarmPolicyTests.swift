import XCTest

@testable import WakeGuard

/// WG-047: pre-alarm-policy configuration. Verifies the domain `PreAlarmPolicy` carries the
/// spec's allowed actions (and still decodes pre-WG-047 data), that `PreAlarmDraft` builds/seeds
/// a policy with the window + actions and keeps the lead time within bounds, that the prompt
/// disclosure states #7 (no response → unchanged) plus the critical-alarm limit, and that the
/// create/edit view model threads the configuration into the built alarm.
@MainActor
final class PreAlarmPolicyTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 47)
    /// 2023-11-14 12:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_699_963_200)

    private func makeVM(editing: Alarm? = nil, _ processor: FakeAlarmCommandProcessor) throws
        -> CreateAlarmViewModel
    {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        return CreateAlarmViewModel(
            editing: editing, processor: processor, clock: TestClock(now: now), ids: ids,
            deviceTimeZone: { zone })
    }

    private func makeAlarm(preAlarm: PreAlarmPolicy) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule, preAlarmPolicy: preAlarm,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    // MARK: - Domain

    func testEnabledCarriesAllowedActions() throws {
        let policy = try PreAlarmPolicy.enabled(
            leadTime: 1800, allowedActions: [.turnOffToday, .remindLater])
        XCTAssertTrue(policy.isEnabled)
        XCTAssertEqual(policy.leadTime, 1800)
        XCTAssertEqual(policy.allowedActions, [.turnOffToday, .remindLater])
    }

    func testDisabledHasNoActions() {
        XCTAssertFalse(PreAlarmPolicy.disabled.isEnabled)
        XCTAssertTrue(PreAlarmPolicy.disabled.allowedActions.isEmpty)
    }

    func testZeroLeadTimeStillThrows() {
        XCTAssertThrowsError(try PreAlarmPolicy.enabled(leadTime: 0))
    }

    func testActionsRoundTripThroughCodable() throws {
        let policy = try PreAlarmPolicy.enabled(leadTime: 900, allowedActions: [.changeTime])
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(PreAlarmPolicy.self, from: data)
        XCTAssertEqual(decoded, policy)
    }

    func testDecodesLegacyPolicyWithoutAllowedActions() throws {
        // Data written before WG-047 (no allowedActions key) must still decode — to an empty set.
        let json = Data(#"{"isEnabled":true,"leadTime":1800}"#.utf8)
        let decoded = try JSONDecoder().decode(PreAlarmPolicy.self, from: json)
        XCTAssertTrue(decoded.isEnabled)
        XCTAssertEqual(decoded.leadTime, 1800)
        XCTAssertTrue(decoded.allowedActions.isEmpty)
    }

    // MARK: - PreAlarmDraft

    func testDefaultDraftBuildsDisabled() {
        XCTAssertEqual(PreAlarmDraft().build(), .disabled)
    }

    func testEnabledDraftBuildsPolicyWithWindowAndActions() {
        var draft = PreAlarmDraft()
        draft.isEnabled = true
        draft.leadTimeMinutes = 45
        draft.allowedActions = [.turnOffToday]

        let policy = draft.build()
        XCTAssertTrue(policy.isEnabled)
        XCTAssertEqual(policy.leadTime, TimeInterval(45 * 60))
        XCTAssertEqual(policy.allowedActions, [.turnOffToday])
    }

    func testLeadTimeIsClampedWithinBounds() {
        var draft = PreAlarmDraft()
        draft.isEnabled = true
        draft.leadTimeMinutes = 100_000  // absurd, above the UI bound

        let policy = draft.build()
        XCTAssertLessThanOrEqual(
            policy.leadTime, TimeInterval(PreAlarmDraft.leadRange.upperBound * 60))
        XCTAssertGreaterThan(policy.leadTime, 0, "the domain requires leadTime > 0")
    }

    func testDraftSeedsFromExistingPolicy() throws {
        let policy = try PreAlarmPolicy.enabled(leadTime: 1200, allowedActions: [.remindLater])
        let draft = PreAlarmDraft(from: policy)
        XCTAssertTrue(draft.isEnabled)
        XCTAssertEqual(draft.leadTimeMinutes, 20)
        XCTAssertEqual(draft.allowedActions, [.remindLater])
    }

    func testPromptDisclosureStatesNoActionPreservesAlarmAndCriticalLimit() {
        let standard = PreAlarmDraft.promptDisclosure(isCritical: false, offersActions: true)
        XCTAssertTrue(
            standard.localizedCaseInsensitiveContains("unchanged"), "#7: no response keeps it")
        XCTAssertFalse(standard.localizedCaseInsensitiveContains("critical"))
        let critical = PreAlarmDraft.promptDisclosure(isCritical: true, offersActions: true)
        XCTAssertTrue(critical.localizedCaseInsensitiveContains("unchanged"))
        XCTAssertTrue(
            critical.localizedCaseInsensitiveContains("confirmation"),
            "the critical-alarm limit is visible")
        // Enabled with no actions is disclosed as an informational-only prompt.
        let empty = PreAlarmDraft.promptDisclosure(isCritical: false, offersActions: false)
        XCTAssertTrue(empty.localizedCaseInsensitiveContains("no options selected"))
        XCTAssertTrue(empty.localizedCaseInsensitiveContains("unchanged"))
    }

    func testDraftSeedsOffStepLeadTimeToTheStepGrid() throws {
        // A policy authored elsewhere (import / migration) with an off-grid lead time seeds to a
        // multiple of the stepper's 5-minute step, so it can't silently desync on first increment.
        let policy = try PreAlarmPolicy.enabled(leadTime: 23 * 60)  // 23 minutes
        let draft = PreAlarmDraft(from: policy)
        XCTAssertEqual(draft.leadTimeMinutes % 5, 0, "seeded lead time aligns to the 5-minute grid")
    }

    // MARK: - View-model integration

    func testDefaultCreateHasNoPreAlarm() async throws {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeVM(processor)

        _ = await vm.save()

        guard case .create(let alarm) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail("expected a create")
        }
        XCTAssertEqual(alarm.preAlarmPolicy, .disabled)
    }

    func testCreateThreadsPreAlarmConfig() async throws {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeVM(processor)
        vm.preAlarm.isEnabled = true
        vm.preAlarm.leadTimeMinutes = 15
        vm.preAlarm.allowedActions = [.turnOffToday, .changeTime]

        _ = await vm.save()

        guard case .create(let alarm) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail("expected a create")
        }
        XCTAssertTrue(alarm.preAlarmPolicy.isEnabled)
        XCTAssertEqual(alarm.preAlarmPolicy.leadTime, TimeInterval(15 * 60))
        XCTAssertEqual(alarm.preAlarmPolicy.allowedActions, [.turnOffToday, .changeTime])
    }

    func testEditSeedsPreAlarmFromExistingAlarm() throws {
        let policy = try PreAlarmPolicy.enabled(leadTime: 600, allowedActions: [.changeTime])
        let existing = try makeAlarm(preAlarm: policy)
        let vm = try makeVM(editing: existing, FakeAlarmCommandProcessor())
        XCTAssertTrue(vm.preAlarm.isEnabled)
        XCTAssertEqual(vm.preAlarm.leadTimeMinutes, 10)
        XCTAssertEqual(vm.preAlarm.allowedActions, [.changeTime])
    }
}
