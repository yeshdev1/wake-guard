import Foundation

/// The live wall clock: `now` is the current system time. The production adapter
/// for the domain's `WallClock` port; deterministic tests use `TestClock` instead.
struct SystemClock: WallClock {
    var now: Date { Date() }
}

/// The live identifier generator: a fresh random UUID per call. The production
/// adapter for the domain's `IdentifierGenerator` port; deterministic tests use
/// `DeterministicIDGenerator` instead.
struct SystemIdentifierGenerator: IdentifierGenerator {
    func next() -> UUID { UUID() }
}
