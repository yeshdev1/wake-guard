import CoreMotion
import Foundation

/// The real CMPedometer-backed historical pedometer (WG-062): queries cumulative step data over a
/// validated window and normalizes each reading to a domain `PedometerSample`, validating it at
/// this boundary (WG-060's deferred validation). It is the only component that reads CMPedometer
/// history, and it **never logs raw samples** (#41) — a query failure surfaces coarsely, never the
/// raw error text or data. An `actor` because it owns a non-Sendable `CMPedometer`.
///
/// Not unit-tested — `CMPedometer` needs a device; the pure window / sample / availability /
/// status-mapping logic is tested in `MotionDomain` instead (see the WG-062 real-device checklist).
actor CoreMotionHistoricalPedometerAdapter: HistoricalPedometerSource {
    private let pedometer = CMPedometer()

    func availability() -> MotionSourceAvailability {
        .forPedometer(
            stepCountingAvailable: CMPedometer.isStepCountingAvailable(),
            authorization: Self.map(CMPedometer.authorizationStatus()))
    }

    func samples(in window: PedometerQueryWindow) async throws -> [PedometerSample] {
        let availability = availability()
        guard availability == .available else {
            throw MotionSourceError.unavailable(availability)
        }
        return [try await querySample(window)]
    }

    private func querySample(_ window: PedometerQueryWindow) async throws -> PedometerSample {
        // A one-shot CoreMotion query has no `stop…` to cancel once in flight, so fail fast if the
        // task is already cancelled before we start (WG-062 review). The in-flight call itself
        // stays uninterruptible — an accepted limitation documented in the ADR.
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(from: window.start, to: window.end) { data, _ in
                guard let data else {
                    // A query error after availability was `.available` is transient — surface it
                    // coarsely, never the raw error text or samples (#41).
                    continuation.resume(
                        throwing: MotionSourceError.unavailable(.temporarilyUnavailable))
                    return
                }
                do {
                    continuation.resume(returning: try Self.sample(from: data, window: window))
                } catch {
                    // A non-nil but corrupt reading fails closed to the same coarse port error the
                    // contract promises — so consumers never see a foreign `MotionQueryError`, and
                    // its value-naming reason string never escapes the adapter (#41).
                    continuation.resume(
                        throwing: MotionSourceError.unavailable(.temporarilyUnavailable))
                }
            }
        }
    }

    /// Normalize one CMPedometerData window into a validated sample, checked against the `window` it
    /// answered (rejects a future/out-of-window timestamp). A historical query gives no per-step
    /// interval, so `secondsSinceLastStep` is nil (cadence *regularity* is the live stream's job,
    /// WG-063).
    static func sample(from data: CMPedometerData, window: PedometerQueryWindow) throws
        -> PedometerSample
    {
        try PedometerSample.validated(
            timestamp: data.endDate, quality: .high, stepCount: data.numberOfSteps.intValue,
            distanceMeters: data.distance?.doubleValue,
            cadenceStepsPerSecond: data.currentCadence?.doubleValue, within: window)
    }

    /// Map CoreMotion's authorization status to the domain's; an unknown future status fails closed
    /// to `.denied` (#27 spirit).
    static func map(_ status: CMAuthorizationStatus) -> MotionAuthorizationStatus {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
