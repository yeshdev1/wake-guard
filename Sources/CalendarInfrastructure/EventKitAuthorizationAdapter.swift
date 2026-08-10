import EventKit
import Foundation

/// Maps the WG-141 authorization port to `EKEventStore` (device-only). Requests **full read** access to
/// events (`requestFullAccessToEvents`) — never write. An errored request fails closed to `.denied`,
/// with no raw error text surfaced (#41). `@unchecked Sendable`: `EKEventStore` is documented thread-safe
/// and the only stored state.
struct EventKitAuthorizationAdapter: CalendarAuthorizationProviding, @unchecked Sendable {
    private let store = EKEventStore()

    func authorizationStatus() async -> CalendarAuthorizationStatus {
        Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    func requestFullAccess() async -> CalendarAuthorizationStatus {
        _ = try? await store.requestFullAccessToEvents()
        return Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    private static func map(_ status: EKAuthorizationStatus) -> CalendarAuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        @unknown default: .denied  // fail closed on any future case
        }
    }
}
