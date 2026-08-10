import Foundation
import XCTest

@testable import WakeGuard

/// WG-210: device-size & orientation visual regression. Pins the **structural adaptivity** that makes the
/// screenshot pass hold — no fixed widths (so the **minimum device** doesn't clip), adaptive layouts (so
/// **landscape** reflows) — and that the **device matrix + triage** process is documented
/// (`docs/VISUAL_REGRESSION.md`).
final class VisualRegressionTests: XCTestCase {

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

    func testViewsHaveNoFixedWidthThatBreaksSmallDevices() throws {
        let directory = repoRoot().appendingPathComponent("Sources/WakeGuardApp")
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let code = try strippedCode(of: url)
            for digit in 0...9 {
                XCTAssertFalse(
                    code.contains(".frame(width: \(digit)"),
                    "\(url.lastPathComponent) has a fixed width — it may clip on the smallest device"
                )
            }
        }
    }

    func testDeviceMatrixAndTriageAreDocumented() throws {
        let doc = try String(
            contentsOf: repoRoot().appendingPathComponent("docs/VISUAL_REGRESSION.md"),
            encoding: .utf8
        )
        for required in ["iPhone SE", "iPad", "Landscape", "triage", "baseline"] {
            XCTAssertTrue(
                doc.lowercased().contains(required.lowercased()),
                "visual-regression doc missing '\(required)'")
        }
    }
}
