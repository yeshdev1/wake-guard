import CoreMotion
import Foundation

/// The real CMMotionActivity **history** query behind the `MotionActivityHistorySource` port (WG-310): a
/// one-shot, foreground-only `queryActivityStarting(from:to:to:)` over an overnight window — **no background
/// execution, no continuous sensing** — mapping each segment to a domain `MotionActivitySample` (reusing the
/// live adapter's `CMMotionActivity` mapping). Unavailable/denied throws (the consumer degrades to "no
/// estimate"), never an empty result read as "undisturbed". Never logs raw activity or CoreMotion state
/// (#41).
///
/// Not unit-tested — `CMMotionActivityManager` needs a device; the pure estimation logic is tested in
/// `MotionDomain` (`SleepDisturbanceEstimatorTests`). An `actor` because it owns a non-Sendable manager.
actor CoreMotionActivityHistoryAdapter: MotionActivityHistorySource {
    private let manager = CMMotionActivityManager()
    private let queue = OperationQueue()

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
        // A one-shot CoreMotion query has no `stop…` to cancel once in flight, so fail fast if already
        // cancelled; the in-flight call itself stays uninterruptible (mirrors the historical pedometer).
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            let handler: CMMotionActivityQueryHandler = { activities, _ in
                guard let activities else {
                    // A query error after `.available` is transient — surface it coarsely, never the raw
                    // error text or activity data (#41).
                    continuation.resume(
                        throwing: MotionSourceError.unavailable(.temporarilyUnavailable))
                    return
                }
                // Reuse the live adapter's mapping; a non-finite-timestamp segment is dropped by `sample()`.
                continuation.resume(
                    returning: activities.compactMap {
                        CMMotionActivityUpdates.reading(from: $0).sample()
                    })
            }
            manager.queryActivityStarting(
                from: window.start, to: window.end, to: queue, withHandler: handler)
        }
    }
}
