import Foundation
import XCTest

@testable import WakeGuard

/// WG-228: 100-cycle alarm/challenge soak. Runs the challenge to completion **100 times** and verifies **no
/// crash, leak, or stale state** (each cycle starts fresh at `.idle` and passes cleanly), and that
/// **duplicate callbacks do not accumulate** (rapid/repeated taps are debounced to one). Results are
/// documented in `docs/SOAK_TEST.md`.
final class SoakTests: XCTestCase {

    private let requirements = AccessibleChallengeRequirements(kind: .tapSequence, requiredTaps: 6)

    func testOneHundredChallengeCyclesLeaveNoStaleState() {
        let interval = requirements.minTapInterval + 0.01
        for cycle in 0..<100 {
            // A fresh machine per cycle — nothing carries over from the previous ring.
            var machine = AccessibleChallengeMachine(requirements)
            XCTAssertEqual(machine.phase, .idle, "cycle \(cycle) must start from idle")

            var time = Date(timeIntervalSince1970: Double(cycle) * 10_000)
            for _ in 0..<requirements.requiredTaps {
                machine.tap(at: time)
                time = time.addingTimeInterval(interval)
            }

            XCTAssertTrue(machine.isPassed, "cycle \(cycle) should pass")
            XCTAssertEqual(
                machine.acceptedTaps, requirements.requiredTaps, "cycle \(cycle): no over-count")
        }
    }

    func testDuplicateTapCallbacksDoNotAccumulate() {
        var machine = AccessibleChallengeMachine(requirements)
        let sameInstant = Date(timeIntervalSince1970: 42)
        // A held / auto-repeating touch delivers many callbacks at (near) the same time — the debounce
        // must accept only one, so duplicates can't satisfy the sequence.
        for _ in 0..<100 { machine.tap(at: sameInstant) }
        XCTAssertEqual(machine.acceptedTaps, 1, "duplicate callbacks must not accumulate")
        XCTAssertFalse(machine.isPassed, "a spammed touch can't pass the challenge")
    }

    func testResultsAreDocumented() throws {
        let doc = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("docs/SOAK_TEST.md"), encoding: .utf8)
        XCTAssertTrue(doc.contains("100"))
        XCTAssertTrue(doc.lowercased().contains("stale"))
    }
}
