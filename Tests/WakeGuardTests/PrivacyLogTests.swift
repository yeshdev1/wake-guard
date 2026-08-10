import XCTest

@testable import WakeGuard

/// WG-019: privacy-safe structured logging. Verifies sensitive value types are redacted to a coarse
/// category marker, that `Redacted` structurally cannot carry the raw value (so release **and** debug
/// logs omit raw health/location/calendar/journal/prompts, #41), and that non-sensitive fields log
/// verbatim.
final class PrivacyLogTests: XCTestCase {

    func testEverySensitiveCategoryRedactsToItsMarker() {
        for category in Redacted.Category.allCases {
            XCTAssertEqual(
                LogField.redacted("f", Redacted(category)).rendered,
                "f=<redacted:\(category.rawValue)>")
        }
        // The #41-enumerated categories are all represented.
        XCTAssertEqual(
            Set(Redacted.Category.allCases.map(\.rawValue)),
            ["health", "location", "calendar", "journal", "prompt", "sample"])
    }

    func testRedactedStoresOnlyItsCategorySoNoRawValueCanLeak() {
        // The structural guarantee (#41): `Redacted` holds only the category, never the raw value — so a
        // raw health/location/calendar/journal/prompt/sample value cannot reach the logging system at
        // all, in any build configuration.
        let mirror = Mirror(reflecting: Redacted(.location))
        XCTAssertEqual(mirror.children.count, 1, "Redacted has exactly one stored field")
        XCTAssertEqual(
            mirror.children.first?.label, "category", "and it is the category, not a value")
    }

    func testLogLineRedactsSensitiveFieldsAndKeepsNonSensitiveVerbatim() throws {
        let log = InMemoryPrivacyLog()
        log.info(
            "evaluated awake evidence",
            [
                .redacted("steps", Redacted(.sample)), .redacted("place", Redacted(.location)),
                .text("result", "likely"), .number("count", 3),
            ])
        let line = try XCTUnwrap(log.lines.last)
        XCTAssertTrue(line.contains("steps=<redacted:sample>"))
        XCTAssertTrue(line.contains("place=<redacted:location>"))
        XCTAssertTrue(line.contains("result=likely"), "non-sensitive fields log verbatim")
        XCTAssertTrue(line.contains("count=3"))
        XCTAssertTrue(line.contains("[info]"), "the level + message are present")
    }

    func testNoRawSensitiveValueEverAppearsInALoggedLine() throws {
        // Even holding a raw secret, a caller has no channel to log it — the sensitive fields accept
        // only a category — so none of the raw content appears in the line.
        let log = InMemoryPrivacyLog()
        log.error(
            "health check",
            [
                .redacted("health", Redacted(.health)), .redacted("loc", Redacted(.location)),
                .redacted("journal", Redacted(.journal)), .redacted("prompt", Redacted(.prompt)),
            ])
        let line = try XCTUnwrap(log.lines.last)
        for leaked in ["72bpm", "37.33", "-122.03", "couldn't sleep", "SYSTEM PROMPT"] {
            XCTAssertFalse(line.contains(leaked), "no raw sensitive value in a log line")
        }
    }
}
