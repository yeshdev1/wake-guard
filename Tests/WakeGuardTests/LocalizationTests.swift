import Foundation
import XCTest

@testable import WakeGuard

/// WG-206: externalize & localize user-facing strings. Verifies **no production string is hard-coded past
/// localization** (SwiftUI `Text` literals are `LocalizedStringKey`s; `Text(verbatim:)` is confined to
/// untrusted content), that a **String Catalog** exists, that **pluralization/interpolation are safe**, and
/// that **permission strings** are present (localizable base).
final class LocalizationTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    // MARK: verbatim confined to untrusted content

    func testVerbatimTextIsOnlyUsedForUntrustedEventTitles() throws {
        let appDir = repoRoot().appendingPathComponent("Sources/WakeGuardApp")
        let enumerator = FileManager.default.enumerator(at: appDir, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let code = try String(contentsOf: url, encoding: .utf8)
            if code.contains("Text(verbatim:") {
                XCTAssertEqual(
                    url.lastPathComponent, "EventTitleText.swift",
                    "Text(verbatim:) bypasses localization — only allowed for untrusted titles")
            }
        }
    }

    // MARK: String Catalog

    func testStringCatalogExistsAndIsValid() throws {
        let data = try Data(contentsOf: repoRoot().appendingPathComponent("Localizable.xcstrings"))
        let catalog = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(catalog["sourceLanguage"] as? String, "en")
        XCTAssertNotNil(catalog["strings"])
    }

    // MARK: safe pluralization / interpolation

    func testCountPhrasingIsPluralAwareAndLocaleFormatted() {
        XCTAssertEqual(LocalizedText.alarmCount(1, locale: Locale(identifier: "en_US")), "1 alarm")
        XCTAssertEqual(LocalizedText.alarmCount(2, locale: Locale(identifier: "en_US")), "2 alarms")
        // The number is locale-formatted (grouping), not a raw String(count).
        let large = LocalizedText.alarmCount(1_000, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(large.contains("1,000"), "count must be locale-formatted: \(large)")
    }

    // MARK: permission strings present (localizable base)

    func testPermissionUsageDescriptionsArePresent() throws {
        let projectYML = try String(
            contentsOf: repoRoot().appendingPathComponent("project.yml"), encoding: .utf8)
        for key in [
            "INFOPLIST_KEY_NSAlarmKitUsageDescription", "INFOPLIST_KEY_NSMotionUsageDescription",
            "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription",
            "INFOPLIST_KEY_NSHealthShareUsageDescription",
            "INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription",
        ] {
            XCTAssertTrue(projectYML.contains(key), "missing permission string '\(key)'")
        }
    }
}
