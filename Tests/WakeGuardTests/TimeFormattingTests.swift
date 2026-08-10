import Foundation
import XCTest

@testable import WakeGuard

/// WG-205: 12/24-hour & locale-aware formatting. Verifies **formatting follows the user locale** (12-hour
/// with AM/PM vs 24-hour), that the **stored schedule stays locale-independent** (numeric, unchanged across
/// locales), and covers **multiple locales and calendars**.
final class TimeFormattingTests: XCTestCase {

    private func time(_ hour: Int, _ minute: Int) throws -> TimeOfDay {
        try TimeOfDay(hour: hour, minute: minute)
    }

    func testTwelveHourLocaleUsesAmPm() throws {
        let morning = TimeFormatting.string(
            for: try time(7, 30), locale: Locale(identifier: "en_US"))
        XCTAssertTrue(morning.lowercased().contains("am"), "en_US morning should be AM: \(morning)")
        let evening = TimeFormatting.string(
            for: try time(20, 0), locale: Locale(identifier: "en_US"))
        XCTAssertTrue(evening.lowercased().contains("pm"), "en_US evening should be PM: \(evening)")
    }

    func testTwentyFourHourLocaleHasNoAmPm() throws {
        let text = TimeFormatting.string(for: try time(20, 0), locale: Locale(identifier: "fr_FR"))
        XCTAssertFalse(text.lowercased().contains("am"))
        XCTAssertFalse(text.lowercased().contains("pm"))
        XCTAssertTrue(text.contains("20"), "fr_FR uses 24-hour: \(text)")
    }

    func testFormattingDiffersByLocaleForTheSameStoredTime() throws {
        let stored = try time(20, 0)
        let us = TimeFormatting.string(for: stored, locale: Locale(identifier: "en_US"))
        let fr = TimeFormatting.string(for: stored, locale: Locale(identifier: "fr_FR"))
        XCTAssertNotEqual(us, fr, "display should follow locale")
    }

    // MARK: stored schedules are locale-independent

    func testStoredTimeIsNumericAndLocaleIndependent() throws {
        let stored = try time(7, 30)
        let data = try JSONEncoder().encode(stored)
        let json = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"hour\""))
        XCTAssertTrue(json.contains("7"))
        XCTAssertFalse(
            json.lowercased().contains("am"), "stored value must carry no locale formatting")
        // Formatting under different locales never mutates the stored value.
        _ = TimeFormatting.string(for: stored, locale: Locale(identifier: "ja_JP"))
        _ = TimeFormatting.string(for: stored, locale: Locale(identifier: "fr_FR"))
        XCTAssertEqual(try JSONDecoder().decode(TimeOfDay.self, from: data), stored)
    }

    // MARK: multiple calendars

    func testTimeOfDayIsStableAcrossCalendars() throws {
        let stored = try time(9, 15)
        var japanese = Calendar(identifier: .japanese)
        japanese.locale = Locale(identifier: "en_US")
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = Locale(identifier: "en_US")
        // The time of day is independent of the calendar system; both render the same wall-clock time.
        let jp = TimeFormatting.string(
            for: stored, locale: Locale(identifier: "en_US"), calendar: japanese)
        let gr = TimeFormatting.string(
            for: stored, locale: Locale(identifier: "en_US"), calendar: gregorian)
        XCTAssertEqual(jp, gr)
    }
}
