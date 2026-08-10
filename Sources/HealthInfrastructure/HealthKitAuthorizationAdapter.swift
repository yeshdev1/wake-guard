import Foundation
import HealthKit

/// Maps the WG-121 authorization port to `HKHealthStore` (device-only). Requests **read** access to
/// exactly the plan's types, mapped to HealthKit object types **here** (the framework boundary) — never
/// share/write (`toShare: []`).
///
/// **Read-authorization caveat:** HealthKit deliberately does not reveal read authorization
/// (`authorizationStatus(for:)` reports only *share* status), so after a successful request this reports
/// `.authorized` — meaning "the user was asked" — and genuine readability is confirmed by whether a query
/// returns data (WG-122), never by this status. A restricted/errored request maps to `.restricted`
/// (fail-closed). `@unchecked Sendable`: `HKHealthStore` is documented thread-safe and the only stored
/// state.
struct HealthKitAuthorizationAdapter: HealthAuthorizationProviding, @unchecked Sendable {
    private let store = HKHealthStore()

    func isHealthDataAvailable() async -> Bool { HKHealthStore.isHealthDataAvailable() }

    func requestReadAccess(to types: Set<WellnessHealthType>) async
        -> [WellnessHealthType: HealthAuthorizationStatus]
    {
        let readTypes = Set(types.compactMap(Self.objectType(for:)))
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            // The request completed (the user saw the sheet). Report `.authorized`; real readability is a
            // query concern (WG-122).
            return statuses(for: types, .authorized)
        } catch {
            // Restricted environment (parental / MDM) or an error — never authorized, fail closed. No raw
            // error text is surfaced (#41).
            return statuses(for: types, .restricted)
        }
    }

    private func statuses(for types: Set<WellnessHealthType>, _ status: HealthAuthorizationStatus)
        -> [WellnessHealthType: HealthAuthorizationStatus]
    {
        Dictionary(uniqueKeysWithValues: types.map { ($0, status) })
    }

    /// The framework boundary — the sole place a `WellnessHealthType` becomes an `HKObjectType`.
    private static func objectType(for type: WellnessHealthType) -> HKObjectType? {
        switch type {
        case .sleepAnalysis: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        }
    }
}
