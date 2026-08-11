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

    // MARK: privacy controls promised by the docs must be wired (WG-250 submission gate)

    func testPrivacyControlsPromisedByDocsAreBackedByProductionCode() throws {
        // The privacy policy + nutrition label promise user export, deletion, and retention. App Review
        // (Guideline 5.1.1(v)/5.1.2) checks label-vs-behavior, so those controls must be backed by
        // PRODUCTION code, not just documented. Today they are NOT: no non-Fake `DataEraser` conformance
        // exists and `RetentionCleanup` has no production caller, so the promise is unmet at runtime
        // (WG-246 Finding 1 / WG-250 BLOCKER 1). This is an EXPECTED FAILURE until E14 wires them; once
        // wired, the assertions pass and `XCTExpectFailure` turns it into an *unexpected pass*, forcing
        // removal of this wrapper. Do NOT delete this test to get green — wire the controls.
        let policy = try String(
            contentsOf: repoRoot().appendingPathComponent("docs/PRIVACY_POLICY.md"), encoding: .utf8
        ).lowercased()
        // Precondition (a real assertion): the docs actually promise these controls.
        XCTAssertTrue(
            policy.contains("delete") && policy.contains("export"),
            "the privacy policy should promise deletion + export")

        let files = try swiftFiles(under: repoRoot().appendingPathComponent("Sources"))
        let contents = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        let hasProductionEraser = contents.contains {
            $0.contains(": DataEraser") || $0.contains(", DataEraser")
        }
        let hasRetentionCaller = zip(files, contents).contains { file, code in
            file.lastPathComponent != "DataRetention.swift" && code.contains("RetentionCleanup")
        }

        XCTExpectFailure(
            "WG-250 BLOCKER: export/deletion/retention are documented but unwired until E14")
        XCTAssertTrue(
            hasProductionEraser,
            "policy promises deletion but no production DataEraser conformance exists in Sources/")
        XCTAssertTrue(
            hasRetentionCaller,
            "policy promises retention but RetentionCleanup has no production caller")
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
