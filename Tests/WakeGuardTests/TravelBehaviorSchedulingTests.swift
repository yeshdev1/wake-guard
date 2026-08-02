import Foundation
import XCTest

@testable import WakeGuard

/// WG-021: wall-clock (follow-local) vs fixed-zone semantics — the two behaviors
/// are distinct, the anchor IANA identifier persists, and the mapping of each
/// `TravelBehavior` to a computation zone is explicit.
final class TravelBehaviorSchedulingTests: XCTestCase {

    private let engine = AlarmSchedulingEngine()
    private let idGenerator = DeterministicIDGenerator(seed: 21)
    private let before = Date(timeIntervalSince1970: 0)  // 1970 — before the 2026 alarm

    private func zone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier))
    }

    /// The instant of 2026-08-15 07:00 wall-clock in `identifier`.
    private func expectedInstant(in identifier: String) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try zone(identifier)
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        components.hour = 7
        components.minute = 0
        components.second = 0
        return try XCTUnwrap(calendar.date(from: components))
    }

    /// A one-time alarm at 2026-08-15 07:00 anchored to `anchor`, with `travel`.
    private func oneTimeAlarm(anchor: String, travel: TravelBehavior) throws -> Alarm {
        let schedule = ScheduleRule.oneTime(
            OneTimeSchedule(
                date: try CalendarDate(year: 2026, month: 8, day: 15),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: anchor)))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(idGenerator.next()), label: "T", schedule: schedule,
            travelBehavior: travel, createdAt: epoch, updatedAt: epoch)
    }

    func testFollowLocalUsesDeviceZone() throws {
        let alarm = try oneTimeAlarm(anchor: "Asia/Tokyo", travel: .followLocal)
        let result = engine.nextOccurrence(
            for: alarm, after: before, deviceTimeZone: try zone("America/New_York"))
        XCTAssertEqual(
            result, try expectedInstant(in: "America/New_York"),
            "follow-local interprets the wall-clock in the device zone")
    }

    func testStayFixedUsesAnchorZone() throws {
        let alarm = try oneTimeAlarm(anchor: "Asia/Tokyo", travel: .stayFixed)
        let result = engine.nextOccurrence(
            for: alarm, after: before, deviceTimeZone: try zone("America/New_York"))
        XCTAssertEqual(
            result, try expectedInstant(in: "Asia/Tokyo"),
            "fixed interprets the wall-clock in the anchor zone regardless of device")
    }

    func testFollowLocalAndFixedAreDistinct() throws {
        // Tokyo and New York have different offsets, so the two intents diverge.
        // (For a same-offset device zone they legitimately coincide — #12 only
        // requires the intents be distinguishable, not that instants always differ.)
        let device = try zone("America/New_York")
        let followLocal = engine.nextOccurrence(
            for: try oneTimeAlarm(anchor: "Asia/Tokyo", travel: .followLocal),
            after: before, deviceTimeZone: device)
        let fixed = engine.nextOccurrence(
            for: try oneTimeAlarm(anchor: "Asia/Tokyo", travel: .stayFixed),
            after: before, deviceTimeZone: device)
        XCTAssertNotEqual(
            followLocal, fixed, "distinct instants when the device differs from the anchor")
    }

    func testAskOnChangeKeepsAnchorZone() throws {
        let alarm = try oneTimeAlarm(anchor: "Asia/Tokyo", travel: .askOnChange)
        let result = engine.nextOccurrence(
            for: alarm, after: before, deviceTimeZone: try zone("America/New_York"))
        XCTAssertEqual(
            result, try expectedInstant(in: "Asia/Tokyo"),
            "ask-on-change safely keeps the original zone until the user resolves it")
    }

    func testRegionRuleFollowsItsSafeFallback() throws {
        let device = try zone("America/New_York")
        let following = try oneTimeAlarm(
            anchor: "Asia/Tokyo",
            travel: .regionRule(RegionRule(regionIdentifier: "home", safeFallback: .followLocal)))
        let fixed = try oneTimeAlarm(
            anchor: "Asia/Tokyo",
            travel: .regionRule(RegionRule(regionIdentifier: "home", safeFallback: .stayFixed)))
        XCTAssertEqual(
            engine.nextOccurrence(for: following, after: before, deviceTimeZone: device),
            try expectedInstant(in: "America/New_York"))
        XCTAssertEqual(
            engine.nextOccurrence(for: fixed, after: before, deviceTimeZone: device),
            try expectedInstant(in: "Asia/Tokyo"))
    }

    func testSchedulingTimeZoneMapping() throws {
        let device = try zone("America/New_York")
        let anchor = try IANATimeZone(identifier: "Asia/Tokyo")
        XCTAssertEqual(
            engine.schedulingTimeZone(for: .followLocal, anchor: anchor, deviceTimeZone: device),
            device)
        XCTAssertEqual(
            engine.schedulingTimeZone(for: .stayFixed, anchor: anchor, deviceTimeZone: device)
                .identifier, "Asia/Tokyo")
        XCTAssertEqual(
            engine.schedulingTimeZone(for: .askOnChange, anchor: anchor, deviceTimeZone: device)
                .identifier, "Asia/Tokyo")
    }

    func testAnchorIANAIdentifierPersistsThroughCodable() throws {
        let alarm = try oneTimeAlarm(anchor: "Asia/Tokyo", travel: .followLocal)
        // Follow-local computes in the device zone, but the stored anchor is unchanged.
        XCTAssertEqual(alarm.schedule.anchorTimeZone.identifier, "Asia/Tokyo")
        let decoded = try JSONDecoder().decode(
            Alarm.self, from: try JSONEncoder().encode(alarm))
        XCTAssertEqual(decoded.schedule.anchorTimeZone.identifier, "Asia/Tokyo")
    }
}
