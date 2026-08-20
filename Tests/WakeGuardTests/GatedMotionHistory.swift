import Foundation
import XCTest

@testable import WakeGuard

// Split out of `ReadinessMovementRefreshOrderingTests` for SwiftLint `file_length` (WG-319). Shared rather
// than duplicated: a second copy of a double this subtle is how one of them silently stops matching the
// dependency it stands in for.

/// Holds queries open so the test can observe the view model *during* a refresh, and interleave two of
/// them. A double that returns immediately makes both the mid-refresh blank and the overlapping-refresh
/// race unobservable — which is why neither was caught.
///
/// Queries are addressed by start order. Indices stay stable across `waitForQueries` because `started` only
/// ever increments — **not** because entries are retained: `take` removes from `pending`, which is precisely
/// what makes completing one twice misuse that fails the test rather than trapping the process on a
/// double-resumed continuation. (An earlier version of this line claimed entries are "**never removed**",
/// contradicted by `take` in the same file.)
actor GatedMotionHistory: MotionActivityHistorySource {
    private var pending: [Int: CheckedContinuation<[MotionActivitySample], any Error>] = [:]
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private var started = 0

    func activitySamples(in window: DateInterval) async throws -> [MotionActivitySample] {
        let id = started
        started += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            while let waiter = arrivals.popLast() { waiter.resume() }
        }
    }

    /// Suspend until at least `count` queries have started, so ordering is deterministic rather than
    /// dependent on how many times the test happens to yield.
    func waitForQueries(_ count: Int) async {
        while started < count {
            await withCheckedContinuation { arrivals.append($0) }
        }
    }

    func finish(_ id: Int, with samples: [MotionActivitySample]) {
        take(id)?.resume(returning: samples)
    }

    func fail(_ id: Int, with error: any Error) {
        take(id)?.resume(throwing: error)
    }

    private func take(_ id: Int) -> CheckedContinuation<[MotionActivitySample], any Error>? {
        guard let continuation = pending.removeValue(forKey: id) else {
            XCTFail("query \(id) was already completed or never started")
            return nil
        }
        return continuation
    }

    deinit {
        // An abandoned continuation otherwise surfaces only as a "leaked its continuation" runtime log.
        // `deinit` is nonisolated, so read the count into a local before asserting on it.
        let abandoned = pending.count
        XCTAssertEqual(abandoned, 0, "a gated query was never completed")
    }
}
