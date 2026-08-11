import Foundation
import SwiftUI
import XCTest

@testable import WakeGuard

/// WG-203: Reduce Motion & haptic alternatives. Verifies moving **animations are removed under Reduce
/// Motion** (and every animated view is Reduce-Motion-gated), that **haptics are supplementary** (paired
/// with a visible state change), and that **progress is understandable** as text without motion/haptics.
final class ReduceMotionTests: XCTestCase {

    func testMovementAnimationIsRemovedUnderReduceMotion() {
        XCTAssertNil(MotionPreference.animation(.spring(), reduceMotion: true))
        XCTAssertNotNil(MotionPreference.animation(.spring(), reduceMotion: false))
    }

    func testCrossFadeIsAllowedUnderReduceMotion() {
        XCTAssertNotNil(MotionPreference.crossFade(reduceMotion: true))
        XCTAssertNotNil(MotionPreference.crossFade(reduceMotion: false))
    }

    func testChallengeProgressIsTextualAndClamped() {
        XCTAssertEqual(MotionPreference.challengeProgressText(counted: 3, required: 10), "3 of 10")
        XCTAssertEqual(
            MotionPreference.challengeProgressText(counted: 12, required: 10), "10 of 10")
    }

    // MARK: every animated view respects Reduce Motion

    func testAllAnimatedViewsAreReduceMotionGated() throws {
        for file in appFiles() {
            let code = try strippedCode(of: file)
            // `withAnimation` is unconditional; the app must use `.animation(reduceMotion ? nil : …)`.
            XCTAssertFalse(
                code.contains("withAnimation("),
                "\(file.lastPathComponent) uses unconditional animation")
            if code.contains(".animation(") {
                XCTAssertTrue(
                    code.contains("reduceMotion"),
                    "\(file.lastPathComponent) animates without a Reduce Motion guard")
            }
        }
    }

    func testTimelineAnimationsAreReduceMotionThrottled() throws {
        // A per-frame `TimelineView(.animation …)` is continuous motion. The file-wide gate above can pass
        // on an unrelated `reduceMotion` mention elsewhere in the file, so pin the construct itself: any
        // TimelineView animation must derive its interval/pause from `reduceMotion` (WG-247).
        for file in appFiles() {
            let code = try strippedCode(of: file)
            guard code.contains("TimelineView(.animation") else { continue }
            XCTAssertTrue(
                code.contains("minimumInterval: reduceMotion")
                    || code.contains("paused: reduceMotion") || code.contains("reduceMotion ?"),
                "\(file.lastPathComponent) has a TimelineView animation not gated on Reduce Motion")
        }
    }

    // MARK: haptics are supplementary (paired with a visible signal)

    func testChallengeHapticIsPairedWithAVisibleSignal() throws {
        let view = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/WakeGuardApp/ChallengeView.swift")
        let code = try strippedCode(of: view)
        // The haptic is driven by a state change (not the sole signal) and the same screen shows visible
        // progress — so a user with haptics off still sees where they are.
        XCTAssertTrue(code.contains("lastHapticCue"), "haptic must be state-derived")
        XCTAssertTrue(code.contains("progressFraction"), "the screen must show visible progress")
    }

    // MARK: helpers

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
}
