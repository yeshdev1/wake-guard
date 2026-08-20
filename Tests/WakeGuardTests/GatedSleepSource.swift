import Foundation
import XCTest

@testable import WakeGuard

// Split out of `ReadinessCardLoadBoundTests` for SwiftLint `file_length` (WG-319), and shared with
// `ReadinessColdOpenClaimTests`. One copy, deliberately: this double's uncooperativeness is load-bearing
// (see below), so a second copy that quietly honoured cancellation would license an inert deadline.

/// An error that is **not** a cancellation, so "the query concluded and failed" is expressible without
/// borrowing `CancellationError` — which the sibling test in `HealthAccessStatesTests` does, and which now
/// means something different on this path.
struct HealthReadFailure: Error {}

/// Holds sleep queries open so a test can observe the card *during* a read and interleave two of them. A
/// double that returns immediately cannot express the hang this file exists to reproduce.
///
/// **Ignores cancellation on purpose.** A deadline implemented as a structured `withTaskGroup` cancels its
/// remaining children and then awaits them on scope exit, so against a source that does not honour
/// cancellation it hangs exactly as before while reading as correct.
///
/// This double is therefore *less* cooperative than the real dependency, not more: both
/// `HealthKitSleepQueryAdapter` and `CoreMotionActivityHistoryAdapter` wrap their continuation in
/// `withTaskCancellationHandler` and resume with `CancellationError` immediately, so the structured form
/// would pass against them today. (An earlier version of this comment asserted the opposite — that they
/// "await a one-shot framework callback that cancellation cannot stop" — which conflated *the callback never
/// firing*, the hazard the deadline exists for, with *the await being uncancellable*, which it is not.)
/// Holding the deadline to the stricter source is deliberate: it keeps the bound from depending on a
/// property of the adapters that nothing in their signatures enforces. See `ReadinessViewModel.firstResult`.
///
/// Queries are addressed by start order. Indices stay stable across `waitForQueries` because `started` only
/// ever increments — **not** because entries are retained: `take` removes from `pending`, which is precisely
/// what makes completing one twice fail the test rather than trapping on a double-resumed continuation. (An
/// earlier version of this line claimed entries are "never removed from `pending`", contradicted by `take`
/// five lines below it.)
actor GatedSleepSource: SleepSampleQuerying {
    private var pending: [Int: CheckedContinuation<[SleepSample], any Error>] = [:]
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private var started = 0

    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
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

    func finish(_ id: Int, with samples: [SleepSample]) {
        take(id)?.resume(returning: samples)
    }

    func fail(_ id: Int, with error: any Error) {
        take(id)?.resume(throwing: error)
    }

    private func take(_ id: Int) -> CheckedContinuation<[SleepSample], any Error>? {
        guard let continuation = pending.removeValue(forKey: id) else {
            XCTFail("query \(id) was already completed or never started")
            return nil
        }
        return continuation
    }

    deinit {
        // An abandoned continuation otherwise surfaces only as a "leaked its continuation" runtime log.
        let abandoned = pending.count
        XCTAssertEqual(abandoned, 0, "a gated query was never completed")
    }
}
