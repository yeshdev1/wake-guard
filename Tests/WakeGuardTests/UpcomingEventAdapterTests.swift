import Foundation
import XCTest

@testable import WakeGuard

/// WG-142: the upcoming-event adapter. Verifies the mapping (all-day + time-zone-aware events map
/// correctly; `hasLocation` is a coarse bool; malformed events are skipped), that queries are **bounded
/// by time** (`EventQueryWindow`) and **by selected calendars** (`CalendarSelection`), and — via a source
/// scan — that the calendar code logs **no raw titles** (it emits no logs at all, #41).
final class UpcomingEventAdapterTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // swiftlint:disable:next function_parameter_count
    private func mapped(
        id: String, start: Date, end: Date, isAllDay: Bool, location: String?, title: String
    ) -> CalendarEvent? {
        CalendarEventMapping.event(
            from: RawEventFields(
                id: id, start: start, end: end, isAllDay: isAllDay, location: location, title: title
            ))
    }

    // MARK: mapping

    func testMappingCarriesFieldsAndDerivesHasLocation() throws {
        let event = try XCTUnwrap(
            mapped(
                id: "e1", start: base, end: base.addingTimeInterval(3_600), isAllDay: false,
                location: "Office", title: "Standup"))
        XCTAssertEqual(event.id, "e1")
        XCTAssertEqual(event.start, base)
        XCTAssertEqual(event.end, base.addingTimeInterval(3_600))
        XCTAssertFalse(event.isAllDay)
        XCTAssertTrue(event.hasLocation)
        XCTAssertEqual(event.title, "Standup")
    }

    func testHasLocationIsFalseForNilOrEmptyLocation() throws {
        for location in [nil, ""] {
            let event = try XCTUnwrap(
                mapped(
                    id: "e", start: base, end: base.addingTimeInterval(60), isAllDay: false,
                    location: location, title: "x"))
            XCTAssertFalse(event.hasLocation)
        }
    }

    func testAllDayEventMapsWithTheFlag() throws {
        let allDay = try XCTUnwrap(
            mapped(
                id: "e", start: base, end: base.addingTimeInterval(86_400), isAllDay: true,
                location: nil, title: "Holiday"))
        XCTAssertTrue(allDay.isAllDay)
        XCTAssertEqual(allDay.end.timeIntervalSince(allDay.start), 86_400)
    }

    func testTimeZoneAwareEventPreservesTheAbsoluteInstant() throws {
        // An event at 09:00 in Tokyo — its absolute instant is carried through unchanged (zone-independent).
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour) = (2026, 6, 15, 9)
        let start = try XCTUnwrap(calendar.date(from: components))
        let event = try XCTUnwrap(
            mapped(
                id: "e", start: start, end: start.addingTimeInterval(3_600), isAllDay: false,
                location: nil, title: "Mtg"))
        XCTAssertEqual(event.start, start, "the absolute instant is preserved")
    }

    func testMalformedEventIsSkipped() {
        XCTAssertNil(
            mapped(
                id: "e", start: base.addingTimeInterval(3_600), end: base, isAllDay: false,
                location: nil, title: "x"))
    }

    // MARK: queries are bounded by time + selected calendars

    func testWindowBoundsAndClampsHorizon() {
        XCTAssertEqual(
            EventQueryWindow(from: base, horizon: 3 * 86_400).end,
            base.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(
            EventQueryWindow(from: base, horizon: 100 * 86_400).end,
            base.addingTimeInterval(EventQueryWindow.maxHorizon), "clamped to the max horizon")
        XCTAssertTrue(EventQueryWindow(from: base, horizon: 0).isEmpty)
        XCTAssertEqual(
            EventQueryWindow(from: base, horizon: .nan).end,
            base.addingTimeInterval(EventQueryWindow.defaultHorizon), "non-finite → default")
    }

    func testCalendarSelectionScopesToChosenCalendars() {
        XCTAssertTrue(CalendarSelection.all.includes("anything"))
        let only = CalendarSelection.only(["work", "family"])
        XCTAssertTrue(only.includes("work"))
        XCTAssertFalse(only.includes("personal"))
    }

    // MARK: no raw titles in logs

    func testCalendarCodeEmitsNoLogs() throws {
        // A title is carried in CalendarEvent (local) — but the calendar code emits no logs at all, so a
        // title can never be written to a log.
        let forbidden = ["print(", "os_log", "Logger(", "NSLog(", "debugPrint("]
        for directory in ["CalendarInfrastructure", "CalendarDomain"] {
            let files = swiftFiles(under: sourcesDirectory().appendingPathComponent(directory))
            XCTAssertFalse(files.isEmpty, "expected sources under \(directory)")
            for file in files {
                let source = try String(contentsOf: file, encoding: .utf8)
                for token in forbidden {
                    XCTAssertFalse(
                        source.contains(token),
                        "\(file.lastPathComponent) logs (\(token)) — a title could leak")
                }
            }
        }
    }

    private func sourcesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    private func swiftFiles(under directory: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }
}
