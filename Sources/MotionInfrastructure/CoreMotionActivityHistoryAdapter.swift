import CoreMotion
import Foundation
import Synchronization

/// The real CMMotionActivity **history** query behind the `MotionActivityHistorySource` port (WG-310): a
/// one-shot, foreground-only `queryActivityStarting(from:to:to:)` over an overnight window — **no background
/// execution, no continuous sensing** — mapping each segment to a domain `MotionActivitySample` (reusing the
/// live adapter's `CMMotionActivity` mapping). Unavailable/denied throws (the consumer degrades to "no
/// estimate"), never an empty result read as "undisturbed". Never logs raw activity or CoreMotion state
/// (#41).
///
/// **Cancelable at the caller, not at the sensor.** Task cancellation resumes with `CancellationError`
/// immediately, with a single-resume guard so the continuation neither leaks nor double-resumes. The query
/// itself keeps running and its handler later no-ops: CoreMotion exposes no way to stop a one-shot history
/// query (unlike `HKHealthStore.stop`, which `HealthKitSleepQueryAdapter` can call). So this bounds how long
/// a caller *waits*, but it cannot promise the handler ever fires — imposing a **deadline** stays the
/// consumer's job (`ReadinessViewModel.summaryBeforeDeadline`), per the `LivePedometerNormalizer` precedent.
///
/// Not unit-tested — `CMMotionActivityManager` needs a device; the pure estimation logic is tested in
/// `MotionDomain` (`SleepDisturbanceEstimatorTests`). An `actor` because it owns a non-Sendable manager.
/// **The cancellation path above is therefore device-verified only** (`SMK-16`); the deadline that makes the
/// user-visible symptom recoverable is covered at the view-model seam, where it is testable.
actor CoreMotionActivityHistoryAdapter: MotionActivityHistorySource {
    private typealias SampleContinuation = CheckedContinuation<[MotionActivitySample], any Error>

    private let manager = CMMotionActivityManager()
    private let queue = OperationQueue()

    /// Guards the single-resume invariant across the two racers: CoreMotion's completion handler (on
    /// `queue`) and the cancellation handler (on whatever thread cancels). A `Mutex` rather than actor
    /// isolation because `onCancel` is nonisolated and runs immediately — it cannot hop to the actor.
    private struct QueryState {
        var continuation: SampleContinuation?
        var resumed = false
    }

    private func availability() -> MotionSourceAvailability {
        .forMotionActivity(
            activityAvailable: CMMotionActivityManager.isActivityAvailable(),
            authorization: CoreMotionHistoricalPedometerAdapter.map(
                CMMotionActivityManager.authorizationStatus()))
    }

    func activitySamples(in window: DateInterval) async throws -> [MotionActivitySample] {
        let availability = availability()
        guard availability == .available else {
            throw MotionSourceError.unavailable(availability)
        }
        try Task.checkCancellation()

        // A cancelled caller must stop *waiting* even though the query itself cannot be stopped. CoreMotion
        // offers no `stop…` for a one-shot history query (unlike `HKHealthStore.stop`, which the sleep
        // adapter next door can call), so cancellation resumes the continuation and leaves the query to
        // finish into a handler that no-ops. Without this the `await` simply never returned: a caller that
        // gave up — a dismissed screen, or `ReadinessViewModel`'s deadline — leaked its continuation and the
        // task holding it for the life of the process.
        let state = Mutex(QueryState())
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: SampleContinuation) in
                let handler: CMMotionActivityQueryHandler = { activities, _ in
                    // `nil` when cancellation already resumed it — a late handler must no-op, not trap on
                    // a double resume.
                    let claimed = state.withLock { current -> SampleContinuation? in
                        guard !current.resumed else { return nil }
                        current.resumed = true
                        return current.continuation
                    }
                    guard let cont = claimed else { return }
                    guard let activities else {
                        // A query error after `.available` is transient — surface it coarsely, never the raw
                        // error text or activity data (#41).
                        cont.resume(
                            throwing: MotionSourceError.unavailable(.temporarilyUnavailable))
                        return
                    }
                    // Reuse the live adapter's mapping; a non-finite-timestamp segment is dropped by
                    // `sample()`.
                    cont.resume(
                        returning: activities.compactMap {
                            CMMotionActivityUpdates.reading(from: $0).sample()
                        })
                }
                // Registering the continuation and starting the query must be ordered against a
                // cancellation that lands in between, so `resumed` is checked under the same lock.
                let cancelledEarly = state.withLock { current -> Bool in
                    if current.resumed { return true }
                    current.continuation = continuation
                    return false
                }
                if cancelledEarly {
                    continuation.resume(throwing: CancellationError())
                } else {
                    manager.queryActivityStarting(
                        from: window.start, to: window.end, to: queue, withHandler: handler)
                }
            }
        } onCancel: {
            let claimed = state.withLock { current -> SampleContinuation? in
                guard !current.resumed else { return nil }
                current.resumed = true
                return current.continuation
            }
            claimed?.resume(throwing: CancellationError())
        }
    }
}
