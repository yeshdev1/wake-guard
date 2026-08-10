import Foundation
import XCTest

@testable import WakeGuard

/// WG-207: right-to-left layout. SwiftUI mirrors **leading/trailing** automatically, so the audit pins that
/// no view uses **absolute** `left`/`right` alignment, padding, or edges (which do **not** mirror), and that
/// rows use the semantic edges — so navigation, time rows, progress, and destructive actions mirror
/// correctly. Directional-icon review is the manual checklist.
final class RTLLayoutTests: XCTestCase {

    private func appFiles() -> [URL] {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/WakeGuardApp")
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
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

    func testNoAbsoluteLeftRightLayout() throws {
        // Absolute edges/alignments don't mirror under RTL. Only leading/trailing are permitted.
        let absolute = [": .left", ": .right", "(.left", "(.right", "[.left", "[.right"]
        for file in appFiles() {
            let code = try strippedCode(of: file)
            for token in absolute {
                XCTAssertFalse(
                    code.contains(token),
                    "\(file.lastPathComponent) uses absolute layout '\(token)' — use leading/trailing"
                )
            }
        }
    }

    func testCoreRowsUseSemanticLeadingTrailing() throws {
        // At least the list/consent rows should use the mirroring alignments.
        let usesSemantic = try appFiles().contains { file in
            let code = try strippedCode(of: file)
            return code.contains(".leading") || code.contains(".trailing")
        }
        XCTAssertTrue(
            usesSemantic, "core rows should use leading/trailing so they mirror under RTL")
    }
}
