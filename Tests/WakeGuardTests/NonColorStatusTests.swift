import Foundation
import XCTest

@testable import WakeGuard

/// WG-204: contrast & non-color status audit. Verifies **every status has text + icon redundancy** (never
/// color alone), that statuses are **distinguishable without color** (distinct labels + icons), that the
/// **critical warning is distinguishable** (a warning glyph), and — via a source scan — that the
/// status-bearing views pair an SF Symbol with text. Dark/light contrast is the manual checklist pass.
final class NonColorStatusTests: XCTestCase {

    func testEveryAlarmStatusHasTextAndIconRedundancy() {
        for style in AlarmStatusStyle.all {
            XCTAssertFalse(style.label.isEmpty, "status has no text label")
            XCTAssertFalse(
                style.systemImage.isEmpty, "status has no icon — color would be the only signal")
        }
    }

    func testAlarmStatusesAreDistinguishableWithoutColor() {
        let labels = AlarmStatusStyle.all.map(\.label)
        let icons = AlarmStatusStyle.all.map(\.systemImage)
        XCTAssertEqual(Set(labels).count, labels.count, "labels must be unique")
        XCTAssertEqual(Set(icons).count, icons.count, "icons must be unique")
    }

    func testCriticalWarningHasADistinctWarningGlyph() {
        XCTAssertTrue(
            AlarmStatusStyle.critical.systemImage.contains("exclamationmark"),
            "the critical status needs a warning glyph, not just a red tint")
        XCTAssertNotEqual(
            AlarmStatusStyle.critical.systemImage, AlarmStatusStyle.scheduled.systemImage)
        XCTAssertNotEqual(AlarmStatusStyle.critical.label, AlarmStatusStyle.scheduled.label)
    }

    // MARK: status-bearing views pair an SF Symbol with text (not color-only)

    func testStatusViewsPairAnIconWithText() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for relative in [
            "Sources/WakeGuardApp/ConsentCenterView.swift",
            "Sources/WakeGuardApp/AIAvailabilitySection.swift",
        ] {
            let code = try String(
                contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            XCTAssertTrue(
                code.contains("Image(systemName") || code.contains("systemImage"),
                "\(relative) status has no icon")
            XCTAssertTrue(code.contains("Text("), "\(relative) status has no text label")
        }
    }
}
