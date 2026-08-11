import Foundation
import XCTest

@testable import WakeGuard

/// WG-260: internal TestFlight build readiness. Pins that **debug-only tools can't ship in a release
/// build** (every debug affordance is `#if DEBUG`-gated, so a release build compiles it out), and that the
/// **build metadata + export config** the pipeline needs are present and consistent. Runs in `ci-fast`, so
/// a change that would leak a debug tool into release — or drop the version/export config — fails CI.
final class ReleaseReadinessTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func contents(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: debug tools are compiled out of release

    func testMotionTraceRecorderIsEntirelyDebugGated() throws {
        // The calibration trace recorder (WG-075) is a debug-only tool; the whole file must open with
        // `#if DEBUG`, so a release build excludes it and shipping code can't reference it.
        let code = try contents("Sources/MotionInfrastructure/MotionTraceRecorder.swift")
        let firstCodeLine = code.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("//") }
        XCTAssertEqual(
            firstCodeLine, "#if DEBUG",
            "the debug-only trace recorder must be entirely #if DEBUG so it can't ship")
    }

    func testUITestingHookIsUnreachableInRelease() throws {
        // The `-uiTesting` in-memory-store hook must sit INSIDE a `#if DEBUG` region so a Release build
        // compiles it out. A file-wide `contains("#if DEBUG")` would pass even if the hook were moved
        // out (as long as any unrelated DEBUG block remained), so walk the guards and assert every
        // `-uiTesting` line is within a debug region (WG-260 review P1-3).
        let directory = repoRoot().appendingPathComponent("Sources/WakeGuardApp")
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let code = try String(contentsOf: url, encoding: .utf8)
            guard code.contains("-uiTesting") else { continue }
            var debugDepth = 0
            for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Only real code can leak the hook — ignore the portion after `//` (a doc comment that
                // merely mentions `-uiTesting` is not a Release-reachable use).
                let codeOnly = String(line).components(separatedBy: "//").first ?? ""
                if trimmed == "#if DEBUG" {
                    debugDepth += 1
                } else if trimmed.hasPrefix("#if"), debugDepth > 0 {
                    debugDepth += 1  // a nested #if inside a debug region
                } else if trimmed == "#endif", debugDepth > 0 {
                    debugDepth -= 1
                } else if codeOnly.contains("-uiTesting") {
                    XCTAssertGreaterThan(
                        debugDepth, 0,
                        "\(url.lastPathComponent): -uiTesting must sit inside #if DEBUG (compiled out "
                            + "of Release)")
                }
            }
        }
    }

    // MARK: release build metadata + export config are present

    func testAppTargetDeclaresExplicitVersionAndBuildNumber() throws {
        let project = try contents("project.yml")
        XCTAssertTrue(
            project.contains("MARKETING_VERSION:"), "an explicit marketing version is required")
        XCTAssertTrue(
            project.contains("CURRENT_PROJECT_VERSION:"), "an explicit build number is required")
    }

    func testExportOptionsTargetAppStoreConnectAndUploadSymbols() throws {
        let export = try contents("ExportOptions.plist")
        XCTAssertTrue(
            export.contains("app-store-connect"),
            "export must target App Store Connect / TestFlight")
        XCTAssertTrue(export.contains("uploadSymbols"), "dSYMs must upload so crashes symbolicate")
    }

    func testReleaseMetadataGeneratorExists() throws {
        let script = try contents("scripts/release_metadata.sh")
        XCTAssertTrue(
            script.contains("build-number"), "the metadata script must emit a build number")
        XCTAssertTrue(
            script.lowercased().contains("release notes"),
            "the metadata script must emit release notes")
    }

    func testReleaseNotesAreSubjectsOnlyNoBodyOrEmail() throws {
        // Release notes must be commit SUBJECTS only — never bodies (%b/%B) or author/committer emails
        // (%ae/%ce/%an), which could carry sensitive detail into a shipped artifact (WG-260 review P2-1).
        let script = try contents("scripts/release_metadata.sh")
        XCTAssertTrue(script.contains("%s"), "release notes must use the commit subject (%s)")
        for leak in ["%b", "%B", "%ae", "%ce", "%an"] {
            XCTAssertFalse(
                script.contains(leak),
                "release notes must not include commit \(leak) — subjects only")
        }
    }
}
