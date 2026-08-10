import Foundation
import XCTest

@testable import WakeGuard

/// WG-188: in-app & web privacy-policy requirements. Verifies the policy doc makes **collection, use,
/// sharing, retention, deletion, and AI providers explicit**, states the **health/motion advertising
/// prohibition**, and provides a **contact path** — so the published policy can't ship missing a required
/// section.
final class PrivacyPolicyRequirementsTests: XCTestCase {

    private func policy() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/PRIVACY_POLICY.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testPolicyCoversEveryRequiredSection() throws {
        let text = try policy()
        for section in [
            "## Collection", "## Use", "## Sharing", "## Retention", "## Deletion",
            "## AI providers",
            "## Contact",
        ] {
            XCTAssertTrue(text.contains(section), "privacy policy is missing '\(section)'")
        }
    }

    func testAIProvidersAreExplicit() throws {
        let text = try policy().lowercased()
        for phrase in ["on device", "cloud ai is off by default", "redacted", "separate"] {
            XCTAssertTrue(text.contains(phrase), "AI-provider disclosure missing '\(phrase)'")
        }
    }

    func testHealthAndMotionAdvertisingProhibitionIsExplicit() throws {
        let text = try policy().lowercased()
        XCTAssertTrue(text.contains("health"))
        XCTAssertTrue(text.contains("motion"))
        XCTAssertTrue(
            text.contains("never used for advertising"),
            "the health/motion advertising prohibition must be explicit")
    }

    func testSharingAndDeletionAndRetentionAreExplicit() throws {
        let text = try policy().lowercased()
        XCTAssertTrue(text.contains("do not share") || text.contains("not share"))
        XCTAssertTrue(text.contains("delete"))
        XCTAssertTrue(text.contains("retain") || text.contains("retention"))
    }

    func testContactPathExists() throws {
        XCTAssertTrue(try policy().contains("@"), "the policy must provide a contact path")
    }
}
