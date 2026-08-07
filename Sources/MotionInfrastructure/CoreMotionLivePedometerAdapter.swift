import CoreMotion
import Foundation
import Synchronization

/// The live CMPedometer stream (WG-063) behind the `PedometerSource` port: cumulative step updates
/// normalized to strictly time-ordered, validated samples. **Cancellation-safe** — it stops
/// CoreMotion updates when the stream terminates or the consuming task is cancelled — and tolerant
/// of duplicate / out-of-order deliveries via `LivePedometerNormalizer`. The CoreMotion dependency
/// is isolated behind the injectable `LivePedometerUpdates` seam (default `CMPedometerLiveUpdates`),
/// so the streaming and cancellation composition is exercised off-device; only the CMPedometer
/// mapping itself is device-only. Never logs raw samples or CoreMotion error text (#41).
struct CoreMotionLivePedometerAdapter: PedometerSource {
    private let updates: LivePedometerUpdates
    private let availabilityProvider: @Sendable () -> MotionSourceAvailability
    private let now: @Sendable () -> Date

    init(
        updates: LivePedometerUpdates = CMPedometerLiveUpdates(),
        availabilityProvider: @escaping @Sendable () -> MotionSourceAvailability = {
            .forPedometer(
                stepCountingAvailable: CMPedometer.isStepCountingAvailable(),
                authorization: CoreMotionHistoricalPedometerAdapter.map(
                    CMPedometer.authorizationStatus()))
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.updates = updates
        self.availabilityProvider = availabilityProvider
        self.now = now
    }

    func availability() async -> MotionSourceAvailability { availabilityProvider() }

    func samples() -> AsyncThrowingStream<PedometerSample, Error> {
        let updates = self.updates
        let availabilityProvider = self.availabilityProvider
        let now = self.now
        return AsyncThrowingStream { continuation in
            let availability = availabilityProvider()
            guard availability == .available else {
                // Unavailable / denied never yields an empty stream — it throws, so the consumer
                // falls back rather than reading silence as "the user didn't move" (#21/#24). No
                // updates were started, so nothing to stop; `onTermination` stays unset.
                continuation.finish(throwing: MotionSourceError.unavailable(availability))
                return
            }
            let state = Mutex(LivePedometerNormalizer())
            continuation.onTermination = { _ in updates.stop() }
            updates.start(from: now()) { reading, error in
                if error != nil {
                    // A live-stream error is terminal; surface it coarsely, never the raw error
                    // text or samples (#41). `finish` triggers `onTermination` → updates stop.
                    continuation.finish(
                        throwing: MotionSourceError.unavailable(.temporarilyUnavailable))
                    return
                }
                guard let reading else { return }
                if let sample = state.withLock({ $0.accept(reading, now: now()) }) {
                    continuation.yield(sample)
                }
            }
        }
    }
}

/// The real CMPedometer live-updates seam (WG-063). Device-only: maps each `CMPedometerData` to a
/// neutral `PedometerReading` and discards the raw CoreMotion error (surfacing only its presence),
/// never logging it (#41). `@unchecked Sendable` because its only stored state is the confined,
/// framework-owned `CMPedometer`, whose own start/stop are the synchronization boundary.
final class CMPedometerLiveUpdates: LivePedometerUpdates, @unchecked Sendable {
    private let pedometer = CMPedometer()
    /// Serializes start/stop so the two never race — makes the `@unchecked Sendable` a *structural*
    /// guarantee (the `CMPedometer` is confined to this queue) rather than a trusted framework
    /// property, and orders a rapid start-then-cancel so `stopUpdates` can never precede its
    /// `startUpdates`.
    private let queue = DispatchQueue(label: "com.wakeguard.pedometer.live")

    func start(from start: Date, handler: @escaping @Sendable (PedometerReading?, Error?) -> Void) {
        queue.async {
            self.pedometer.startUpdates(from: start) { data, error in
                handler(data.map(Self.reading(from:)), error)
            }
        }
    }

    func stop() { queue.async { self.pedometer.stopUpdates() } }

    /// CMPedometer live data has no per-step interval, so `secondsSinceLastStep` is left nil here
    /// (see `PedometerReading`); WG-069/070 reconstruct cadence regularity downstream.
    static func reading(from data: CMPedometerData) -> PedometerReading {
        PedometerReading(
            timestamp: data.endDate, stepCount: data.numberOfSteps.intValue,
            distanceMeters: data.distance?.doubleValue,
            cadenceStepsPerSecond: data.currentCadence?.doubleValue)
    }
}
