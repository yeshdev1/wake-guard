import Foundation
import XCTest

@testable import WakeGuard

/// WG-026: the AlarmKit adapter's error mapping — the one part of the (otherwise
/// device-only) adapter that is unit-testable. Verifies #41 redaction (a coarse
/// reason, never leaked error text) and that a cancelled operation maps to
/// `.uncertain` so the caller reconciles rather than assuming it did not happen (#10).
final class SystemAlarmManagerAdapterTests: XCTestCase {

    private struct SensitiveError: Error {
        let detail = "take insulin 20u at home 37.331,-122.031"
    }

    func testErrorMappingIsCoarseAndRedacted() {
        let mapped = SystemAlarmManagerAdapter.map(SensitiveError())
        guard case .failed(let reason) = mapped else {
            return XCTFail("expected .failed, got \(mapped)")
        }
        XCTAssertEqual(reason, "The alarm could not be scheduled.")
        XCTAssertFalse(reason.contains("insulin"), "no sensitive text leaks into the reason (#41)")
        XCTAssertFalse(reason.contains("37.33"))
    }

    func testCancellationMapsToUncertain() {
        XCTAssertEqual(SystemAlarmManagerAdapter.map(CancellationError()), .uncertain)
    }
}
