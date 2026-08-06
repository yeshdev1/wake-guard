import XCTest

@testable import WakeGuard

/// WG-043: the edit / enable / disable / delete flows. Verifies row actions submit the right
/// command through the processor, that a critical destructive action asks for confirmation
/// (#6) and re-submits confirmed, that a failure surfaces a reason and leaves the alarm
/// unchanged, and that editing pre-fills and submits an `.update`.
@MainActor
final class AlarmEditFlowTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 43)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeAlarm(criticality: Criticality = .standard, enabled: Bool = true) throws
        -> Alarm
    {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", isEnabled: enabled, schedule: schedule,
            criticality: criticality, createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    private func makeListVM(_ processor: FakeAlarmCommandProcessor, seeded: [Alarm]) async throws
        -> AlarmListViewModel
    {
        let repo = CoreDataAlarmRepository(try PersistenceController(inMemory: true))
        for alarm in seeded { try await repo.save(alarm) }
        let vm = AlarmListViewModel(
            alarms: repo, clock: TestClock(now: now), processor: processor, deviceTimeZone: { .gmt }
        )
        await vm.load()
        return vm
    }

    private func makeEditVM(_ alarm: Alarm, _ processor: FakeAlarmCommandProcessor) throws
        -> CreateAlarmViewModel
    {
        // A geographic zone: `TimeZone(identifier: "UTC").identifier` normalizes to "GMT",
        // which `IANATimeZone` rejects (#11), so the device zone must be a real tz-database id.
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        return CreateAlarmViewModel(
            editing: alarm, processor: processor, clock: TestClock(now: now), ids: ids,
            deviceTimeZone: { zone })
    }

    // MARK: - Enable / disable / delete route through the processor

    func testDisableSubmitsDisableCommand() async throws {
        let alarm = try makeAlarm()
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try await makeListVM(processor, seeded: [alarm])
        await vm.setEnabled(false, for: alarm.id)
        XCTAssertEqual(processor.seen, [.disable(alarm.id)])
        XCTAssertNil(vm.pendingConfirmation)
    }

    func testEnableSubmitsEnableCommand() async throws {
        let alarm = try makeAlarm(enabled: false)
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try await makeListVM(processor, seeded: [alarm])
        await vm.setEnabled(true, for: alarm.id)
        XCTAssertEqual(processor.seen, [.enable(alarm.id)])
    }

    func testDeleteSubmitsDeleteCommand() async throws {
        let alarm = try makeAlarm()
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try await makeListVM(processor, seeded: [alarm])
        await vm.delete(alarm.id)
        XCTAssertEqual(processor.seen, [.delete(alarm.id)])
    }

    // MARK: - Critical destructive confirmation (#6)

    func testCriticalDestructiveActionConfirmsThenReSubmits() async throws {
        let alarm = try makeAlarm(criticality: .critical)
        let processor = FakeAlarmCommandProcessor(
            unconfirmed: .needsConfirmation(reason: "This is a critical alarm. Confirm."),
            confirmed: .applied)
        let vm = try await makeListVM(processor, seeded: [alarm])

        await vm.delete(alarm.id)
        let pending = try XCTUnwrap(
            vm.pendingConfirmation, "a rejected critical delete must prompt")
        XCTAssertEqual(pending.command, .delete(alarm.id))
        XCTAssertFalse(pending.reason.isEmpty)

        await vm.confirmPending()
        XCTAssertNil(vm.pendingConfirmation)
        XCTAssertEqual(
            processor.seen, [.delete(alarm.id), .delete(alarm.id)],
            "re-submitted with confirmation")
    }

    func testCancellingConfirmationLeavesAlarmUnchanged() async throws {
        let alarm = try makeAlarm(criticality: .critical)
        let processor = FakeAlarmCommandProcessor(
            unconfirmed: .needsConfirmation(reason: "Confirm."), confirmed: .applied)
        let vm = try await makeListVM(processor, seeded: [alarm])

        await vm.delete(alarm.id)
        XCTAssertNotNil(vm.pendingConfirmation)
        await vm.cancelPendingConfirmation()

        XCTAssertNil(vm.pendingConfirmation)
        XCTAssertEqual(processor.seen, [.delete(alarm.id)], "the confirmed delete never ran")
    }

    func testActionFailureSurfacesErrorAndLeavesSafeState() async throws {
        let alarm = try makeAlarm()
        let processor = FakeAlarmCommandProcessor(
            outcome: .failed(reason: "The alarm could not be saved."))
        let vm = try await makeListVM(processor, seeded: [alarm])

        await vm.setEnabled(false, for: alarm.id)

        XCTAssertEqual(vm.actionError, "The alarm could not be saved.")
        XCTAssertNil(vm.pendingConfirmation, "a hard failure is not a confirmation prompt")
    }

    func testNonConfirmableRejectionSurfacesErrorNotPrompt() async throws {
        // A fail-closed policy `.rejected` (e.g. a transient storage read error) is NOT
        // confirmable: it must surface as an error, never a "Confirm change" prompt whose
        // Confirm re-submits into the same rejection.
        let alarm = try makeAlarm(criticality: .critical)
        let processor = FakeAlarmCommandProcessor(
            outcome: .rejected(reason: "We can’t check this alarm right now."))
        let vm = try await makeListVM(processor, seeded: [alarm])

        await vm.delete(alarm.id)

        XCTAssertNil(vm.pendingConfirmation, "a non-confirmable rejection is not a prompt")
        XCTAssertEqual(vm.actionError, "We can’t check this alarm right now.")
        XCTAssertEqual(processor.seen, [.delete(alarm.id)], "not re-submitted")
    }

    // MARK: - Edit (update)

    func testEditingSubmitsUpdateWithSameIdBumpedRevisionPreservedFields() async throws {
        let alarm = try makeAlarm(criticality: .critical)  // revision 0, critical
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeEditVM(alarm, processor)
        vm.label = "renamed"

        let result = await vm.save()

        XCTAssertEqual(result, .created)
        guard case .update(let updated) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail("edit must submit an .update")
        }
        XCTAssertEqual(updated.id, alarm.id)
        XCTAssertEqual(updated.label, "renamed")
        XCTAssertEqual(updated.criticality, .critical, "criticality is preserved (WG-044 edits it)")
        XCTAssertEqual(updated.revision, 1, "revision bumps for optimistic concurrency")
    }

    func testEditingCriticalAlarmNeedsConfirmation() async throws {
        let alarm = try makeAlarm(criticality: .critical)
        let processor = FakeAlarmCommandProcessor(
            unconfirmed: .needsConfirmation(reason: "Confirm."), confirmed: .applied)
        let vm = try makeEditVM(alarm, processor)
        vm.label = "renamed"

        guard case .needsConfirmation = await vm.save() else {
            return XCTFail("editing a critical alarm must ask for confirmation (#6)")
        }
    }

    func testEditingPreFillsFromExistingAlarm() throws {
        let alarm = try makeAlarm()
        let vm = try makeEditVM(alarm, FakeAlarmCommandProcessor())
        XCTAssertTrue(vm.isEditing)
        XCTAssertEqual(vm.label, "wake")
        XCTAssertEqual(vm.kind, .weekly)
        XCTAssertEqual(vm.weekdays, Set(Weekday.allCases))
    }

    // MARK: - WG-044: editing criticality

    func testEditSeedsCriticalToggleAndCanWeakenIt() async throws {
        let alarm = try makeAlarm(criticality: .critical)
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeEditVM(alarm, processor)
        XCTAssertTrue(vm.isCritical, "editing a critical alarm pre-fills the toggle on")

        vm.isCritical = false  // weaken; the policy gates this in production, the VM just submits
        _ = await vm.save()

        guard case .update(let updated) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail("edit must submit an .update")
        }
        XCTAssertEqual(
            updated.criticality, .standard, "the toggle lowers the submitted criticality")
    }
}
