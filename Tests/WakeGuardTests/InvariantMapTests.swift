import Foundation
import XCTest

@testable import WakeGuard

/// WG-240 (Epoch 1): pins that the architecture/invariant review **maps every one of the 50 safety
/// invariants** to code + tests, and that discovered **violations are recorded as blocking issues** — so a
/// dropped mapping or a swept-under finding fails CI.
final class InvariantMapTests: XCTestCase {

    private func mapDoc() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("docs/reviews/EPOCH_01_INVARIANT_MAP.md"), encoding: .utf8)
    }

    func testEveryInvariantOneThroughFiftyIsMapped() throws {
        let doc = try mapDoc()
        for invariant in 1...50 {
            XCTAssertTrue(
                doc.contains("| \(invariant) |"),
                "invariant #\(invariant) is not mapped in the epoch-1 review")
        }
    }

    func testBlockingFindingsAreRecorded() throws {
        let doc = try mapDoc()
        // Violations must become tracked blocking issues, and the P0 verdict must be explicit.
        XCTAssertTrue(doc.lowercased().contains("no open p0"))
        XCTAssertTrue(doc.contains("P1"), "the anti-shake gap must be recorded as a blocking issue")
        XCTAssertTrue(doc.contains("WG-243"), "the P1 must be assigned an owner")
    }
}
