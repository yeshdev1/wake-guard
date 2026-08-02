import Foundation

@testable import WakeGuard

/// A deterministic `WallClock` for tests: time does not advance on its own — it
/// changes only via `advance(by:)` or `set(_:)`. The `WallClock` port itself is a
/// production type (`AppComposition`), promoted from TestSupport in WG-018.
final class TestClock: WallClock {
    private let storage: Synchronized<Date>

    /// Defaults to the Unix epoch so tests start from a fixed, obvious instant.
    init(now: Date = Date(timeIntervalSince1970: 0)) {
        storage = Synchronized(now)
    }

    var now: Date { storage.get() }

    func advance(by interval: TimeInterval) {
        storage.mutate { $0 += interval }
    }

    func set(_ date: Date) {
        storage.mutate { $0 = date }
    }
}
