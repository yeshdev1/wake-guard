import Foundation
import XCTest

@testable import WakeGuard

/// WG-202: Dynamic Type & layout stress. Verifies (statically) that the app stays legible at the largest
/// accessibility sizes — **fonts scale** (no fixed point sizes; everything is a semantic/`DesignSystem`
/// font), there is **no horizontal scrolling** in the UI, and long screens are **scrollable** so content
/// isn't clipped and controls stay reachable. The pixel-level pass at the largest size is the manual audit
/// in `docs/ACCESSIBILITY_CHECKLIST.md`.
final class DynamicTypeLayoutTests: XCTestCase {

    private func appAndDesignFiles() -> [URL] {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        var files: [URL] = []
        for module in ["WakeGuardApp", "DesignSystem"] {
            let directory = sources.appendingPathComponent(module)
            let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "swift" { files.append(url) }
            }
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

    func testFontsScaleNoFixedPointSizes() throws {
        // A fixed-size font does not respond to Dynamic Type. All fonts must be semantic / DesignSystem.
        for file in appAndDesignFiles() {
            let code = try strippedCode(of: file)
            for fixed in [".system(size:", "Font.system(size:", ".font(.system(size:"] {
                XCTAssertFalse(
                    code.contains(fixed),
                    "\(file.lastPathComponent) uses a fixed font size '\(fixed)'")
            }
        }
    }

    func testNoHorizontalScrolling() throws {
        for file in appAndDesignFiles() {
            let code = try strippedCode(of: file)
            for horizontal in ["ScrollView(.horizontal", "axes: .horizontal", "[.horizontal]"] {
                XCTAssertFalse(
                    code.contains(horizontal),
                    "\(file.lastPathComponent) scrolls horizontally ('\(horizontal)')")
            }
        }
    }

    func testLongContentScreensAreScrollable() throws {
        // The consent center is the longest content screen; it must scroll so large type stays reachable.
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/WakeGuardApp/ConsentCenterView.swift")
        XCTAssertTrue(
            try strippedCode(of: file).contains("ScrollView"),
            "the consent center must be scrollable for large Dynamic Type")
    }
}
