import Foundation

/// A wall-clock time source (`now` as a `Date`). Application code reads "now"
/// through this port so tests can make time deterministic (CLAUDE.md: route all
/// time reads through an injected clock abstraction). Named `WallClock` to avoid
/// overloading the stdlib's duration-based `Swift.Clock`.
///
/// A domain-owned port (like `Repositories`): the live `SystemClock` and the
/// deterministic `TestClock` are supplied from outer layers (AppComposition /
/// TestSupport), so the domain stays framework-independent.
protocol WallClock: Sendable {
    var now: Date { get }
}
