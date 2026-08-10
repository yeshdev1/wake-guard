import Foundation
import XCTest

@testable import WakeGuard

/// WG-191: App Review notes & demo mode. Verifies the notes explain **how a reviewer tests alarms and
/// optional permissions**, that **safety behavior is explained**, and that **no fake capability is
/// claimed** — and that the demo content is **real** alarm data, not simulated behavior.
final class AppReviewNotesTests: XCTestCase {

    private func notes() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/APP_REVIEW_NOTES.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testNotesCoverRequiredSections() throws {
        let text = try notes()
        for section in [
            "## Testing alarms", "## Testing optional permissions", "## Safety behavior",
            "## No fake capabilities", "## Contact",
        ] {
            XCTAssertTrue(text.contains(section), "App Review notes missing '\(section)'")
        }
    }

    func testNotesExplainAlarmAndPermissionTesting() throws {
        let text = try notes().lowercased()
        XCTAssertTrue(text.contains("create an alarm") || text.contains("create a real alarm"))
        XCTAssertTrue(text.contains("optional"), "must state optional permissions")
        XCTAssertTrue(
            text.contains("denied"), "must state the app works with permissions denied")
    }

    func testNotesExplainSafetyBehavior() throws {
        let text = try notes().lowercased()
        XCTAssertTrue(text.contains("advisory"))
        XCTAssertTrue(text.contains("policy engine") || text.contains("audited"))
        XCTAssertTrue(text.contains("critical alarms require"))
    }

    func testNotesClaimNoFakeCapabilities() throws {
        let text = try notes().lowercased()
        XCTAssertTrue(text.contains("on the device") || text.contains("on-device"))
        XCTAssertTrue(text.contains("cloud ai is off by default"))
        XCTAssertTrue(text.contains("no medical"))
        XCTAssertTrue(text.contains("no third-party sdk"))
    }

    // MARK: demo content is real, valid alarm data

    func testDemoContentIsRealAndValid() {
        let samples = ReviewDemoContent.sampleAlarms
        XCTAssertFalse(samples.isEmpty)
        for sample in samples {
            XCTAssertFalse(sample.label.isEmpty)
            XCTAssertTrue((0...23).contains(sample.hour))
            XCTAssertTrue((0...59).contains(sample.minute))
            XCTAssertFalse(sample.weekdays.isEmpty, "a weekly sample needs at least one day")
        }
        // Includes a critical and a non-critical example so both behaviors can be reviewed.
        XCTAssertTrue(samples.contains { $0.isCritical })
        XCTAssertTrue(samples.contains { !$0.isCritical })
    }
}
