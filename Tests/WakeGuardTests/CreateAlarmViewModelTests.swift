import XCTest

@testable import WakeGuard

/// WG-042: the create-alarm view model. Verifies each MVP schedule type builds and submits a
/// `.create` command, that the live next-occurrence preview doubles as validation (a
/// past-only or day-less alarm can't be saved), and that a deferred sync still counts as
/// created while a real failure surfaces its reason.
@MainActor
final class CreateAlarmViewModelTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 42)
    /// 2023-11-14 12:00:00 UTC — a fixed, mid-day instant.
    private let now = Date(timeIntervalSince1970: 1_699_963_200)

    private func makeVM(
        _ processor: FakeAlarmCommandProcessor
    ) throws -> CreateAlarmViewModel {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        return CreateAlarmViewModel(
            processor: processor, clock: TestClock(now: now), ids: ids, deviceTimeZone: { zone })
    }

    func testWeeklyAlarmBuildsAndSubmitsCreateCommand() async throws {
        let processor = FakeAlarmCommandProcessor(outcome: .uncertain)
        let vm = try makeVM(processor)
        vm.label = "  Wake up  "
        vm.kind = .weekly

        XCTAssertTrue(vm.canSave, "a weekly alarm with the default days is always saveable")
        let result = await vm.save()

        XCTAssertEqual(result, .created)
        XCTAssertEqual(processor.seen.count, 1)
        guard case .create(let alarm) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail(
                "expected a .create command, got \(String(describing: processor.seen.first))")
        }
        XCTAssertEqual(alarm.label, "Wake up", "the label is trimmed")
        guard case .weekly(let weekly) = alarm.schedule else {
            return XCTFail("expected a weekly schedule")
        }
        XCTAssertEqual(weekly.days.days, Set(Weekday.allCases))
        XCTAssertEqual(
            weekly.time, try TimeOfDay(hour: 7, minute: 0), "07:00 EST from the 12:00 UTC clock")
        XCTAssertEqual(
            weekly.timeZone.identifier, "America/New_York", "anchored to the device zone")
    }

    func testWeeklyWithNoDaysCannotBeSaved() async throws {
        let processor = FakeAlarmCommandProcessor()
        let vm = try makeVM(processor)
        vm.kind = .weekly
        vm.weekdays = []

        XCTAssertNil(vm.nextOccurrence, "no weekdays means the alarm can never ring")
        XCTAssertFalse(vm.canSave)
        let result = await vm.save()
        XCTAssertEqual(result, .invalid)
        XCTAssertTrue(processor.seen.isEmpty, "an unsaveable alarm is never submitted")
    }

    func testOneTimeInThePastCannotBeSaved() async throws {
        let processor = FakeAlarmCommandProcessor()
        let vm = try makeVM(processor)
        vm.kind = .oneTime
        vm.date = now.addingTimeInterval(-10 * 24 * 3600)  // ten days ago

        XCTAssertNil(vm.nextOccurrence, "a one-time date in the past has no upcoming occurrence")
        XCTAssertFalse(vm.canSave)
    }

    func testOneTimeInTheFutureCanBeSaved() async throws {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeVM(processor)
        vm.kind = .oneTime
        vm.date = now.addingTimeInterval(10 * 24 * 3600)  // ten days ahead

        XCTAssertNotNil(vm.nextOccurrence)
        XCTAssertTrue(vm.canSave)
        let result = await vm.save()
        XCTAssertEqual(result, .created)
        guard case .create(let alarm) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail("expected a .create command")
        }
        guard case .oneTime = alarm.schedule else { return XCTFail("expected a one-time schedule") }
    }

    func testPreviewUpdatesLiveAsTheFormChanges() async throws {
        let vm = try makeVM(FakeAlarmCommandProcessor())
        vm.kind = .weekly
        XCTAssertNotNil(vm.nextOccurrence)
        vm.weekdays = []
        XCTAssertNil(vm.nextOccurrence, "clearing the days removes the upcoming occurrence")
        vm.weekdays = [.monday]
        XCTAssertNotNil(vm.nextOccurrence, "re-adding a day restores it")
    }

    func testDeferredSyncStillCountsAsCreated() async throws {
        // The interim adapter reports `.uncertain` (system scheduling deferred) — the alarm is
        // still persisted, so the create succeeds.
        let vm = try makeVM(FakeAlarmCommandProcessor(outcome: .uncertain))
        let result = await vm.save()
        XCTAssertEqual(result, .created)
    }

    func testSaveFailureSurfacesReason() async throws {
        let vm = try makeVM(
            FakeAlarmCommandProcessor(outcome: .failed(reason: "The alarm could not be saved.")))
        let result = await vm.save()
        XCTAssertEqual(result, .failed(reason: "The alarm could not be saved."))
    }

    func testOneTimeThatLapsedSincePreviewIsNotSaved() async throws {
        // The chosen minute passes between the preview (Save enabled) and the Save tap:
        // `save()` re-validates future-ness and refuses to persist a dead alarm.
        let processor = FakeAlarmCommandProcessor()
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let clock = TestClock(now: now)
        let vm = CreateAlarmViewModel(
            processor: processor, clock: clock, ids: ids, deviceTimeZone: { zone })
        vm.kind = .oneTime
        vm.date = now.addingTimeInterval(120)  // ~2 minutes ahead → saveable at preview time
        vm.time = now.addingTimeInterval(120)
        XCTAssertTrue(vm.canSave)

        clock.advance(by: 3600)  // an hour passes; the chosen instant is now in the past
        let result = await vm.save()

        XCTAssertEqual(result, .invalid, "a lapsed one-time is re-validated at save and refused")
        XCTAssertTrue(processor.seen.isEmpty, "no dead alarm is submitted")
    }

    func testOneTimeSubmitsExactScheduleFields() async throws {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeVM(processor)
        vm.kind = .oneTime
        vm.date = now.addingTimeInterval(10 * 24 * 3600)  // 2023-11-24 (EST)

        _ = await vm.save()

        guard case .create(let alarm) = try XCTUnwrap(processor.seen.first),
            case .oneTime(let schedule) = alarm.schedule
        else { return XCTFail("expected a one-time create") }
        XCTAssertEqual(schedule.time, try TimeOfDay(hour: 7, minute: 0))
        XCTAssertEqual(schedule.date, try CalendarDate(year: 2023, month: 11, day: 24))
        XCTAssertEqual(schedule.timeZone.identifier, "America/New_York")
    }

    func testOneTimeTodayEarlierTimeCannotBeSaved() async throws {
        let vm = try makeVM(FakeAlarmCommandProcessor())
        vm.kind = .oneTime
        vm.date = now
        vm.time = now.addingTimeInterval(-3600)  // an hour before now, same day

        XCTAssertNil(vm.nextOccurrence, "today, but an earlier time, has no upcoming occurrence")
        XCTAssertFalse(vm.canSave)
    }

    func testEmptyLabelCreatesUnlabeledAlarm() async throws {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeVM(processor)
        vm.label = "   "

        let result = await vm.save()

        XCTAssertEqual(result, .created)
        guard case .create(let alarm) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail("expected a create")
        }
        XCTAssertEqual(alarm.label, "", "a blank label is stored empty (the list shows a default)")
    }

    // MARK: - WG-044: criticality

    func testNewAlarmDefaultsToStandard() async throws {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeVM(processor)
        XCTAssertFalse(vm.isCritical, "a new alarm is standard unless the user opts in")

        _ = await vm.save()

        guard case .create(let alarm) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail("expected a create")
        }
        XCTAssertEqual(alarm.criticality, .standard)
    }

    func testCriticalToggleSubmitsCriticalAlarm() async throws {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeVM(processor)
        vm.isCritical = true

        _ = await vm.save()

        guard case .create(let alarm) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail("expected a create")
        }
        XCTAssertEqual(alarm.criticality, .critical, "the toggle makes the built alarm critical")
    }
}
