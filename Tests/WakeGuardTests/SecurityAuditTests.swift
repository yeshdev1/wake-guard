import Foundation
import XCTest

@testable import WakeGuard

/// WG-189: static security & dependency audit. Verifies **no known-vulnerable dependency** (zero
/// third-party), that **network endpoints and entitlements are inventoried and match the code** (no
/// outbound network in the shipped app; only the HealthKit entitlement), and that the audit doc records the
/// **triaged findings**.
final class SecurityAuditTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func strippedCode(of file: URL) throws -> String {
        let contents = try String(contentsOf: file, encoding: .utf8)
        var result = ""
        for raw in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") {
                continue
            }
            if let comment = line.range(of: "//") {
                result += line[line.startIndex..<comment.lowerBound] + "\n"
            } else {
                result += line + "\n"
            }
        }
        return result
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

    // MARK: no outbound network endpoints

    func testSourcesHaveNoOutboundNetworkEndpoints() throws {
        for file in swiftFiles(under: repoRoot().appendingPathComponent("Sources")) {
            let code = try strippedCode(of: file)
            for token in ["URLSession", "URLRequest", "dataTask", "https://", "http://"] {
                XCTAssertFalse(
                    code.contains(token),
                    "\(file.lastPathComponent) has a network endpoint '\(token)'")
            }
            // The only permitted URL construction opens the system Settings app.
            if code.contains("URL(string:") {
                XCTAssertTrue(
                    code.contains("openSettingsURLString"),
                    "\(file.lastPathComponent) builds a URL that isn't the Settings opener")
            }
        }
    }

    // MARK: entitlements inventory

    func testOnlyHealthKitEntitlementIsDeclared() throws {
        let data = try Data(contentsOf: repoRoot().appendingPathComponent("WakeGuard.entitlements"))
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(Set(plist.keys), ["com.apple.developer.healthkit"])
    }

    // MARK: no third-party dependencies

    func testNoThirdPartyDependencies() throws {
        let projectYML = try String(
            contentsOf: repoRoot().appendingPathComponent("project.yml"), encoding: .utf8)
        for external in ["packages:", "- package:", "github:"] {
            XCTAssertFalse(
                projectYML.contains(external), "unexpected external dependency '\(external)'")
        }
    }

    // MARK: audit doc records the triaged findings

    func testAuditDocInventoriesEndpointsEntitlementsAndFindings() throws {
        let doc = try String(
            contentsOf: repoRoot().appendingPathComponent("docs/SECURITY_AUDIT.md"), encoding: .utf8
        )
        for required in [
            "openSettingsURLString", "com.apple.developer.healthkit", "Findings & triage",
            "Accepted",
        ] {
            XCTAssertTrue(doc.contains(required), "security audit doc missing '\(required)'")
        }
    }
}
