import Foundation

/// A wall-clock time source (`now` as a `Date`). Production reads "now" through
/// this port so tests can make time deterministic (CLAUDE.md: route all time
/// reads through an injected clock abstraction). Named `WallClock` to avoid
/// overloading the stdlib's duration-based `Swift.Clock`.
///
/// WG-007 defines it in TestSupport; promote to a production port module when
/// production first consumes it (WG-018/WG-020), per ADR-003.
protocol WallClock: Sendable {
    var now: Date { get }
}

/// A deterministic `WallClock` for tests: time does not advance on its own — it
/// changes only via `advance(by:)` or `set(_:)`.
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
