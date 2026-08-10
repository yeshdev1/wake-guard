import Foundation
import XCTest

@testable import WakeGuard

/// WG-209: aesthetic consistency. Enforces that views draw **spacing, corner radius, and color from the
/// `DesignSystem`** rather than raw literals — so spacing, typography, iconography, and corner treatment
/// stay consistent across screens. (Typography is also pinned by WG-202; the before/after visual pass is in
/// `docs/AESTHETIC_CONSISTENCY.md`.)
final class AestheticConsistencyTests: XCTestCase {

    private func viewFiles() -> [URL] {
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

    func testViewsUseDesignSystemTokensNotRawValues() throws {
        var forbidden = [
            "Color.red", "Color.green", "Color.blue", "Color.orange", "Color.yellow", "Color.gray",
            "Color.purple", "Color.pink",
        ]
        for digit in 0...9 {
            forbidden.append(".padding(\(digit)")
            forbidden.append(".cornerRadius(\(digit)")
        }
        // `spacing: 0` (tight stacking) is idiomatic and allowed; a non-zero raw spacing is not.
        for digit in 1...9 { forbidden.append("spacing: \(digit)") }

        for file in viewFiles() {
            let code = try strippedCode(of: file)
            for token in forbidden {
                XCTAssertFalse(
                    code.contains(token),
                    "\(file.lastPathComponent) uses raw '\(token)' — use a DesignSystem token")
            }
        }
    }

    func testReviewDocExists() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/AESTHETIC_CONSISTENCY.md")
        XCTAssertTrue(
            try String(contentsOf: url, encoding: .utf8).lowercased().contains("visual hierarchy"))
    }
}
