import Foundation
import XCTest

@testable import WakeGuard

/// WG-186: privacy manifest & SDK inventory. Verifies `PrivacyInfo.xcprivacy` declares **no tracking** and
/// the **required-reason APIs actually used** (UserDefaults), that the app ships **no third-party SDK**,
/// and that the manifest stays **consistent with the code** (a required-reason API used in `Sources/` is
/// declared).
final class PrivacyManifestTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func manifest() throws -> [String: Any] {
        let url = repoRoot().appendingPathComponent("PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    private func accessedAPIReasons(_ manifest: [String: Any], category: String) -> [String] {
        let types = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        for type in types where type["NSPrivacyAccessedAPIType"] as? String == category {
            return type["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        }
        return []
    }

    // MARK: no tracking

    func testManifestDeclaresNoTracking() throws {
        let manifest = try manifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertTrue((manifest["NSPrivacyTrackingDomains"] as? [Any] ?? [1]).isEmpty)
        XCTAssertTrue((manifest["NSPrivacyCollectedDataTypes"] as? [Any] ?? [1]).isEmpty)
    }

    // MARK: required-reason APIs are documented

    func testManifestDeclaresTheUserDefaultsRequiredReason() throws {
        let reasons = accessedAPIReasons(
            try manifest(), category: "NSPrivacyAccessedAPICategoryUserDefaults")
        XCTAssertTrue(reasons.contains("CA92.1"), "UserDefaults access must declare a reason")
    }

    // MARK: manifest is consistent with the code

    func testRequiredReasonAPIsUsedInCodeAreDeclared() throws {
        let sources = repoRoot().appendingPathComponent("Sources")
        let usesUserDefaults = try swiftFiles(under: sources).contains { file in
            (try? String(contentsOf: file, encoding: .utf8))?.contains("UserDefaults") == true
        }
        XCTAssertTrue(usesUserDefaults, "expected UserDefaults use in Sources")
        // Since the code uses UserDefaults, the manifest must declare it — otherwise App Review rejects.
        XCTAssertFalse(
            accessedAPIReasons(try manifest(), category: "NSPrivacyAccessedAPICategoryUserDefaults")
                .isEmpty,
            "code uses UserDefaults but the manifest doesn't declare the required reason")
    }

    // MARK: no third-party SDKs

    func testProjectHasNoThirdPartySDKDependencies() throws {
        let projectYML = try String(
            contentsOf: repoRoot().appendingPathComponent("project.yml"), encoding: .utf8)
        // XcodeGen declares external SPM packages under a top-level `packages:` and per-target
        // `- package:` references. First-party target deps use `- target:`. Assert none of the external
        // forms appear.
        for external in ["packages:", "- package:", "url:", "github:"] {
            XCTAssertFalse(
                projectYML.contains(external),
                "project.yml declares an external SDK dependency ('\(external)') — none is permitted"
            )
        }
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }
}
