import Foundation

/// Source of unique identifiers. Application code generates ids through this port
/// so deterministic tests can inject a reproducible sequence (CLAUDE.md: route UUID
/// generation through an injected identifier generator in deterministic tests).
///
/// A domain-owned port: the live `SystemIdentifierGenerator` and the deterministic
/// `DeterministicIDGenerator` are supplied from outer layers.
protocol IdentifierGenerator: Sendable {
    func next() -> UUID
}
