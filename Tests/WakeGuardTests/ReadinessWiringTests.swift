import Foundation
import XCTest

@testable import WakeGuard

/// WG-131 composition (wiring E2): the readiness card is driven by a real sleep source composed in the
/// graph, and degrades **safely** with no data — an unavailable "not enough data" assessment, never a
/// fabricated score (#36/#38). Health is optional; this is the path the simulator / an ineligible device
/// takes.
@MainActor
final class ReadinessWiringTests: XCTestCase {

    func testGraphSleepQueryDrivesReadinessThatDegradesSafely() async throws {
        let env = try AppEnvironment.inMemory()
        let model = ReadinessViewModel(sleepQuery: env.sleepQuery)

        await model.refresh(now: Date(timeIntervalSince1970: 1_700_000_000))

        let assessment = try XCTUnwrap(model.assessment, "readiness computes even with no data")
        XCTAssertNil(
            assessment.weightedScore,
            "no sleep data → unavailable readiness, never a fabricated score (#36/#38)")
        XCTAssertTrue(assessment.factors.isEmpty, "no factors when there's no data")
    }
}
