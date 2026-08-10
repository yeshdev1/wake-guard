import Foundation

@testable import WakeGuard

/// A recording `HealthAuthorizationProviding` for tests: a configurable device availability + canned
/// per-type statuses, capturing the exact type set it was asked for (to assert only-necessary-types).
actor RecordingHealthAuthorizationProvider: HealthAuthorizationProviding {
    private let available: Bool
    private let statuses: [WellnessHealthType: HealthAuthorizationStatus]
    private(set) var lastRequested: Set<WellnessHealthType>?

    init(available: Bool = true, statuses: [WellnessHealthType: HealthAuthorizationStatus] = [:]) {
        self.available = available
        self.statuses = statuses
    }

    func isHealthDataAvailable() -> Bool { available }

    func requestReadAccess(to types: Set<WellnessHealthType>)
        -> [WellnessHealthType: HealthAuthorizationStatus]
    {
        lastRequested = types
        return Dictionary(uniqueKeysWithValues: types.map { ($0, statuses[$0] ?? .notDetermined) })
    }
}
