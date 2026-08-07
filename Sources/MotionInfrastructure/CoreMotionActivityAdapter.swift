import CoreMotion
import Foundation

/// The live CMMotionActivity stream (WG-064) behind the `MotionActivitySource` port: each
/// classification is resolved to a single domain kind (conservatively) and tagged with the
/// classifier's confidence + timestamp. **Cancellation-safe** — it stops CoreMotion updates when
/// the stream terminates or the consuming task is cancelled. The CoreMotion dependency is isolated
/// behind the injectable `MotionActivityUpdates` seam (default `CMMotionActivityUpdates`), so the
/// streaming/cancellation composition is exercised off-device; only the `CMMotionActivity` mapping
/// is device-only. The mapping is stateless (activity is not cumulative), so no lock is needed.
/// Never logs raw activity or CoreMotion state (#41).
struct CoreMotionActivityAdapter: MotionActivitySource {
    private let updates: MotionActivityUpdates
    private let availabilityProvider: @Sendable () -> MotionSourceAvailability

    init(
        updates: MotionActivityUpdates = CMMotionActivityUpdates(),
        availabilityProvider: @escaping @Sendable () -> MotionSourceAvailability = {
            .forMotionActivity(
                activityAvailable: CMMotionActivityManager.isActivityAvailable(),
                authorization: CoreMotionHistoricalPedometerAdapter.map(
                    CMMotionActivityManager.authorizationStatus()))
        }
    ) {
        self.updates = updates
        self.availabilityProvider = availabilityProvider
    }

    func availability() async -> MotionSourceAvailability { availabilityProvider() }

    func samples() -> AsyncThrowingStream<MotionActivitySample, Error> {
        let updates = self.updates
        let availabilityProvider = self.availabilityProvider
        return AsyncThrowingStream { continuation in
            let availability = availabilityProvider()
            guard availability == .available else {
                // Unavailable / unsupported never yields an empty stream — it throws, so the
                // consumer falls back rather than reading silence as evidence (#21/#24). No updates
                // were started, so nothing to stop; `onTermination` stays unset.
                continuation.finish(throwing: MotionSourceError.unavailable(availability))
                return
            }
            continuation.onTermination = { _ in updates.stop() }
            updates.start { reading in
                // A nil reading or a non-finite-timestamp one is dropped, never emitted.
                guard let sample = reading?.sample() else { return }
                continuation.yield(sample)
            }
        }
    }
}

/// The real CMMotionActivity live-updates seam (WG-064). Device-only: maps each `CMMotionActivity`
/// to a neutral `MotionActivityReading` (flags + confidence + start date). `@unchecked Sendable`
/// because its only stored state is the framework-owned `CMMotionActivityManager` + its queues,
/// confined here; start/stop are serialized on `controlQueue` so they never race (making the
/// `@unchecked` a structural guarantee) and a rapid start-then-cancel can't stop before it starts.
final class CMMotionActivityUpdates: MotionActivityUpdates, @unchecked Sendable {
    private let manager = CMMotionActivityManager()
    private let deliveryQueue = OperationQueue()
    private let controlQueue = DispatchQueue(label: "com.wakeguard.motionactivity.control")

    func start(handler: @escaping @Sendable (MotionActivityReading?) -> Void) {
        controlQueue.async {
            self.manager.startActivityUpdates(to: self.deliveryQueue) { activity in
                handler(activity.map(Self.reading(from:)))
            }
        }
    }

    func stop() { controlQueue.async { self.manager.stopActivityUpdates() } }

    static func reading(from activity: CMMotionActivity) -> MotionActivityReading {
        MotionActivityReading(
            timestamp: activity.startDate, quality: quality(from: activity.confidence),
            stationary: activity.stationary, walking: activity.walking, running: activity.running,
            cycling: activity.cycling, automotive: activity.automotive, unknown: activity.unknown)
    }

    /// Map CoreMotion's classifier confidence to the domain trust axis; an unknown future confidence
    /// fails conservative to `.low` (least-trusted — #27 spirit).
    static func quality(from confidence: CMMotionActivityConfidence) -> MotionSampleQuality {
        switch confidence {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        @unknown default: return .low
        }
    }
}
