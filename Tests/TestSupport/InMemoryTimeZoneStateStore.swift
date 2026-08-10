import Foundation

@testable import WakeGuard

/// An in-memory `TimeZoneStateStore` for tests. Thread-safe (reference type).
final class InMemoryTimeZoneStateStore: TimeZoneStateStore {
    private let state: Synchronized<IANATimeZone?>

    init(_ initial: IANATimeZone? = nil) {
        state = Synchronized(initial)
    }

    func lastKnownZone() -> IANATimeZone? { state.get() }

    func setLastKnownZone(_ zone: IANATimeZone) {
        state.mutate { $0 = zone }
    }
}
