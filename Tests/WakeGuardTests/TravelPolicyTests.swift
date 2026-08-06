import XCTest

@testable import WakeGuard

/// WG-046: travel-policy configuration. Verifies the three MVP options map to/from the domain
/// `TravelBehavior` (a region rule maps to Ask), that each option is distinct with a
/// plain-language destination preview, that the create/edit view model threads the choice into
/// the built alarm and seeds it when editing, and that the anchor IANA zone is exposed.
@MainActor
final class TravelPolicyTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 46)
    /// 2023-11-14 12:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_699_963_200)

    private func makeVM(
        editing: Alarm? = nil, zone: String = "America/New_York",
        _ processor: FakeAlarmCommandProcessor
    ) throws -> CreateAlarmViewModel {
        let timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return CreateAlarmViewModel(
            editing: editing, processor: processor, clock: TestClock(now: now), ids: ids,
            deviceTimeZone: { timeZone })
    }

    private func makeAlarm(travel: TravelBehavior) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule, travelBehavior: travel,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    // MARK: - TravelOption mapping

    func testOptionRoundTripsThroughBehavior() {
        XCTAssertEqual(TravelOption.followLocal.behavior, .followLocal)
        XCTAssertEqual(TravelOption.keepZone.behavior, .stayFixed)
        XCTAssertEqual(TravelOption.ask.behavior, .askOnChange)
        XCTAssertEqual(TravelOption(from: .followLocal), .followLocal)
        XCTAssertEqual(TravelOption(from: .stayFixed), .keepZone)
        XCTAssertEqual(TravelOption(from: .askOnChange), .ask)
    }

    func testRegionRuleMapsToAsk() {
        let rule = TravelBehavior.regionRule(
            RegionRule(regionIdentifier: "home", safeFallback: .stayFixed))
        XCTAssertEqual(TravelOption(from: rule), .ask, "a region rule maps to Ask in the MVP")
    }

    func testEveryOptionHasADistinctTitleAndPreview() {
        // Acceptance 1: the three options must be clear + distinguishable.
        let titles = Set(TravelOption.allCases.map(\.title))
        XCTAssertEqual(
            titles.count, TravelOption.allCases.count, "each option has a distinct title")
        // Acceptance 2: the preview describes destination behavior in plain language.
        XCTAssertTrue(
            TravelOption.followLocal.destinationDescription(timeText: "7:00 AM", zone: "New York")
                .localizedCaseInsensitiveContains("local time"))
        XCTAssertTrue(
            TravelOption.keepZone.destinationDescription(timeText: "7:00 AM", zone: "New York")
                .contains("New York"))
        XCTAssertTrue(
            TravelOption.ask.destinationDescription(timeText: "7:00 AM", zone: "New York")
                .localizedCaseInsensitiveContains("ask before"))
    }

    func testEditingInAnotherZonePreservesTheStoredAnchor() async throws {
        // A "keep home-zone" alarm anchored to New York, edited while the device is in Tokyo,
        // must NOT silently re-anchor to Tokyo (#16 — no silent zone shift on a fixed alarm).
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "America/New_York")))
        let epoch = Date(timeIntervalSince1970: 0)
        let nyAlarm = try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule,
            travelBehavior: .stayFixed, createdAt: epoch, updatedAt: epoch, revision: 0)
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeVM(editing: nyAlarm, zone: "Asia/Tokyo", processor)

        XCTAssertEqual(vm.anchorZoneID, "America/New_York", "the stored anchor is shown, not Tokyo")

        _ = await vm.save()
        guard case .update(let updated) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail("expected an update")
        }
        XCTAssertEqual(
            updated.schedule.anchorTimeZone.identifier, "America/New_York",
            "editing abroad must not silently re-anchor the schedule (#16)")
    }

    func testPreviewCopyNeverImpliesLocationTracking() {
        // A future copy edit must not reintroduce a location-tracking implication, and the ask
        // option must keep its #16 assurance.
        for option in TravelOption.allCases {
            let text =
                option.destinationDescription(timeText: "7:00 AM", zone: "New York") + " "
                + option.title
            for forbidden in ["gps", "location", "track"] {
                XCTAssertFalse(
                    text.localizedCaseInsensitiveContains(forbidden),
                    "\(option) copy must not imply \(forbidden)")
            }
        }
        XCTAssertTrue(
            TravelOption.ask.destinationDescription(timeText: "7:00 AM", zone: "New York")
                .localizedCaseInsensitiveContains("never moves the alarm on its own"),
            "the ask option must keep its #16 assurance")
    }

    // MARK: - View-model integration

    func testDefaultCreateFollowsLocal() async throws {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeVM(processor)

        _ = await vm.save()

        guard case .create(let alarm) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail("expected a create")
        }
        XCTAssertEqual(alarm.travelBehavior, .followLocal)
    }

    func testChosenOptionThreadsIntoCreatedAlarm() async throws {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeVM(processor)
        vm.travel = .keepZone

        _ = await vm.save()

        guard case .create(let alarm) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail("expected a create")
        }
        XCTAssertEqual(alarm.travelBehavior, .stayFixed)
    }

    func testEditSeedsTravelFromExistingAlarm() throws {
        let existing = try makeAlarm(travel: .askOnChange)
        let vm = try makeVM(editing: existing, FakeAlarmCommandProcessor())
        XCTAssertEqual(vm.travel, .ask)
    }

    func testAnchorZoneIsTheDeviceZone() throws {
        let vm = try makeVM(zone: "Europe/London", FakeAlarmCommandProcessor())
        XCTAssertEqual(vm.anchorZoneID, "Europe/London")
    }
}
