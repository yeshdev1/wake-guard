import Foundation
import XCTest

@testable import WakeGuard

/// WG-208: sleep-inertia usability review. Verifies the ringing/challenge screens have **minimal choices**
/// (few controls), **short copy**, and **no accidental destructive taps** (no destructive control on a wake
/// screen) — so a groggy user can't misfire.
final class SleepInertiaTests: XCTestCase {

    private let wakeScreens = ["ChallengeView.swift", "AccessibleChallengeView.swift"]

    private func source(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/WakeGuardApp/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testWakeScreensHaveMinimalChoices() throws {
        for screen in wakeScreens {
            let buttons = try source(screen).components(separatedBy: "Button").count - 1
            XCTAssertLessThanOrEqual(
                buttons, SleepInertiaGuidelines.maxWakeScreenActions,
                "\(screen) has too many controls for a wake screen")
        }
    }

    func testWakeScreensHaveNoDestructiveAction() throws {
        for screen in wakeScreens {
            let code = try source(screen)
            XCTAssertFalse(
                code.contains("role: .destructive"),
                "\(screen) must not expose a destructive action on a wake screen")
        }
    }

    func testWakeScreenCopyIsShort() throws {
        for screen in wakeScreens {
            for literal in textLiterals(in: try source(screen)) {
                XCTAssertLessThanOrEqual(
                    literal.count, SleepInertiaGuidelines.maxWakeCopyCharacters,
                    "\(screen) copy is too long for a half-asleep user: \"\(literal)\"")
            }
        }
    }

    func testReviewDocExists() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/SLEEP_INERTIA_REVIEW.md")
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("Minimal choices"))
    }

    /// Extracts `Text("…")` string-literal contents from source.
    private func textLiterals(in code: String) -> [String] {
        var literals: [String] = []
        var remainder = Substring(code)
        while let start = remainder.range(of: "Text(\"") {
            let afterOpen = start.upperBound
            if let end = remainder[afterOpen...].firstIndex(of: "\"") {
                literals.append(String(remainder[afterOpen..<end]))
                remainder = remainder[end...]
            } else {
                break
            }
        }
        return literals
    }
}
