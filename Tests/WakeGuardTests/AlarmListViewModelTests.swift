import XCTest

@testable import WakeGuard

/// WG-041: the alarm-list view model. Verifies the state transitions (loading → empty /
/// loaded / failed) and the `Alarm` → list-item mapping (status, next occurrence, next-ring
/// text, the next-alarm summary). Critically, a failed load is `.failed`, **never** `.empty`
/// — a storage failure must not look like "no alarms" (#10).
@MainActor
final class AlarmListViewModelTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 41)
    /// 2023-11-14 22:13:20 UTC — both test alarms (06:00 / 09:00 UTC) fire the next day.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRepo() throws -> CoreDataAlarmRepository {
        CoreDataAlarmRepository(try PersistenceController(inMemory: true))
    }

    private func makeVM(_ alarms: any AlarmRepository) -> AlarmListViewModel {
        AlarmListViewModel(alarms: alarms, clock: TestClock(now: now), deviceTimeZone: { .gmt })
    }

    private func makeAlarm(
        hour: Int, enabled: Bool = true, criticality: Criticality = .standard,
        label: String = "wake"
    ) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: hour, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: label, isEnabled: enabled, schedule: schedule,
            criticality: criticality, createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    private func loadedContent(_ vm: AlarmListViewModel) async throws -> AlarmListContent {
        await vm.load()
        return try XCTUnwrap(vm.state.loadedContent, "expected .loaded, got \(vm.state)")
    }

    func testEmptyRepositoryLoadsEmptyState() async throws {
        let vm = makeVM(try makeRepo())
        await vm.load()
        XCTAssertEqual(vm.state, .empty)
    }

    func testLoadFailurePresentsFailedNotEmpty() async throws {
        let vm = makeVM(FailingAlarmRepository())
        await vm.load()
        guard case .failed(let reason) = vm.state else {
            return XCTFail("a failed load must be .failed, never .empty (#10) — got \(vm.state)")
        }
        XCTAssertFalse(reason.isEmpty, "the failure is user-displayable")
    }

    func testReconcileRunsThroughTheProcessorThenReloads() async throws {
        // WG-029: launch/foreground reconciles the system authority against saved alarms, then the
        // list refreshes and the reconciling banner clears.
        let repo = try makeRepo()
        try await repo.save(makeAlarm(hour: 7))
        let processor = FakeAlarmCommandProcessor()
        let vm = AlarmListViewModel(
            alarms: repo, clock: TestClock(now: now), processor: processor, deviceTimeZone: { .gmt }
        )

        await vm.reconcile()

        XCTAssertEqual(processor.reconcileCount, 1, "reconciliation runs through the processor")
        XCTAssertFalse(vm.isReconciling, "the reconciling banner clears when the pass finishes")
        guard case .loaded = vm.state else {
            return XCTFail("reconcile refreshes the list, got \(vm.state)")
        }
    }

    func testReconcileWithoutProcessorStillReloads() async throws {
        // A read-only context (WG-041 previews/tests) has no processor → reconcile just reloads safely.
        let repo = try makeRepo()
        try await repo.save(makeAlarm(hour: 7))
        let vm = makeVM(repo)

        await vm.reconcile()

        guard case .loaded = vm.state else {
            return XCTFail("reconcile with no processor still loads, got \(vm.state)")
        }
    }

    func testLoadedComputesNextAlarmSummaryAsSoonest() async throws {
        let repo = try makeRepo()
        let early = try makeAlarm(hour: 6, label: "early")
        let late = try makeAlarm(hour: 9, label: "late")
        try await repo.save(late)
        try await repo.save(early)

        let content = try await loadedContent(makeVM(repo))

        XCTAssertEqual(content.items.count, 2)
        XCTAssertEqual(content.nextAlarm?.id, early.id, "the soonest upcoming alarm is the summary")
        XCTAssertEqual(content.items.first?.id, early.id, "the list is sorted soonest-first")
    }

    func testEnabledStandardAlarmIsScheduledWithUpcomingRing() async throws {
        let repo = try makeRepo()
        try await repo.save(try makeAlarm(hour: 6))
        let content = try await loadedContent(makeVM(repo))

        let item = try XCTUnwrap(content.items.first)
        XCTAssertEqual(item.status.label, "Scheduled")
        XCTAssertNotNil(item.nextOccurrence)
        XCTAssertGreaterThan(try XCTUnwrap(item.nextOccurrence), now)
        XCTAssertNotEqual(item.nextRingText, "Off")
    }

    func testDisabledAlarmIsOffWithNoNextOccurrence() async throws {
        let repo = try makeRepo()
        try await repo.save(try makeAlarm(hour: 6, enabled: false))
        let content = try await loadedContent(makeVM(repo))

        let item = try XCTUnwrap(content.items.first)
        XCTAssertEqual(item.status.label, "Off")
        XCTAssertNil(item.nextOccurrence)
        XCTAssertEqual(item.nextRingText, "Off")
        XCTAssertNil(content.nextAlarm, "a disabled alarm is never the next alarm")
    }

    func testCriticalAlarmHasCriticalStatus() async throws {
        let repo = try makeRepo()
        try await repo.save(try makeAlarm(hour: 6, criticality: .critical))
        let content = try await loadedContent(makeVM(repo))

        XCTAssertEqual(content.items.first?.status.label, "Critical")
    }

    func testItemsAreSortedByNextOccurrence() async throws {
        let repo = try makeRepo()
        try await repo.save(try makeAlarm(hour: 9, label: "c"))
        try await repo.save(try makeAlarm(hour: 6, label: "a"))
        try await repo.save(try makeAlarm(hour: 7, label: "b"))

        let content = try await loadedContent(makeVM(repo))

        let occurrences = content.items.compactMap(\.nextOccurrence)
        XCTAssertEqual(occurrences, occurrences.sorted(), "rows ascend by next fire time")
        XCTAssertEqual(content.items.map(\.label), ["a", "b", "c"])
    }

    func testEnabledAlarmWithNoUpcomingOccurrenceIsAttention() async throws {
        let repo = try makeRepo()
        let epoch = Date(timeIntervalSince1970: 0)
        let past = try Alarm(
            id: AlarmID(ids.next()), label: "old", isEnabled: true,
            schedule: .oneTime(
                OneTimeSchedule(
                    date: try CalendarDate(year: 2020, month: 1, day: 1),
                    time: try TimeOfDay(hour: 7, minute: 0),
                    timeZone: try IANATimeZone(identifier: "UTC"))),
            createdAt: epoch, updatedAt: epoch, revision: 0)
        try await repo.save(past)

        let content = try await loadedContent(makeVM(repo))
        let item = try XCTUnwrap(content.items.first)
        XCTAssertEqual(item.status.label, "Needs attention")
        XCTAssertNil(item.nextOccurrence)
        XCTAssertEqual(item.nextRingText, "No upcoming time")
        XCTAssertNil(content.nextAlarm, "an alarm with no upcoming time is not the next alarm")
    }

    func testEmptyLabelFallsBackToAlarm() async throws {
        let repo = try makeRepo()
        try await repo.save(try makeAlarm(hour: 6, label: ""))
        let content = try await loadedContent(makeVM(repo))
        XCTAssertEqual(content.items.first?.label, "Alarm")
    }

    func testReloadRecomputesAgainstAdvancedClock() async throws {
        let repo = try makeRepo()
        try await repo.save(try makeAlarm(hour: 6))
        let clock = TestClock(now: now)
        let vm = AlarmListViewModel(alarms: repo, clock: clock, deviceTimeZone: { .gmt })

        await vm.load()
        let first = try XCTUnwrap(vm.state.loadedContent?.items.first?.nextOccurrence)
        clock.advance(by: 2 * 24 * 3600)  // two days later
        await vm.load()
        let second = try XCTUnwrap(vm.state.loadedContent?.items.first?.nextOccurrence)
        XCTAssertGreaterThan(second, first, "reload recomputes the next occurrence against now")
    }

    func testCriticalAlarmLeadsAccessibilityLabelWithCriticality() async throws {
        let repo = try makeRepo()
        try await repo.save(try makeAlarm(hour: 6, criticality: .critical, label: "meds"))
        let content = try await loadedContent(makeVM(repo))
        let item = try XCTUnwrap(content.items.first)
        XCTAssertTrue(
            item.accessibilityLabel.hasPrefix("Critical alarm."),
            "VoiceOver announces criticality first")
    }

    func testDisabledAlarmAccessibilityLabelDoesNotRepeatOff() async throws {
        let repo = try makeRepo()
        try await repo.save(try makeAlarm(hour: 6, enabled: false, label: "nap"))
        let content = try await loadedContent(makeVM(repo))
        XCTAssertEqual(content.items.first?.accessibilityLabel, "nap, Off")
    }

    func testSetReconcilingTogglesTheFlag() async throws {
        let vm = makeVM(try makeRepo())
        XCTAssertFalse(vm.isReconciling)
        vm.setReconciling(true)
        XCTAssertTrue(vm.isReconciling)
        vm.setReconciling(false)
        XCTAssertFalse(vm.isReconciling)
    }
}

extension AlarmListState {
    /// The loaded content, or nil — lets a test `XCTUnwrap` it (failing, not skipping, on a
    /// wrong state).
    fileprivate var loadedContent: AlarmListContent? {
        if case .loaded(let content) = self { return content }
        return nil
    }
}

/// An alarm repository whose reads always throw — proves the list fails to `.failed`, not
/// `.empty` (#10).
private struct FailingAlarmRepository: AlarmRepository {
    func save(_ alarm: Alarm) async throws { throw AlarmRepositoryError.storageUnavailable }
    func alarm(id: AlarmID) async throws -> Alarm? { throw AlarmRepositoryError.storageUnavailable }
    func allAlarms() async throws -> [Alarm] { throw AlarmRepositoryError.storageUnavailable }
    func deleteAlarm(id: AlarmID) async throws { throw AlarmRepositoryError.storageUnavailable }
}
