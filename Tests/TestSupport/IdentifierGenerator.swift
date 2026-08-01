import Foundation

/// Source of unique identifiers. Production injects a real generator; tests
/// inject `DeterministicIDGenerator` so IDs are reproducible (CLAUDE.md: route
/// UUID generation through an injected identifier generator in deterministic
/// tests).
protocol IdentifierGenerator: Sendable {
    func next() -> UUID
}

/// Produces a reproducible sequence of UUIDs from a monotonic counter. The same
/// `seed` always yields the same sequence, so ordering-sensitive tests are
/// stable.
final class DeterministicIDGenerator: IdentifierGenerator {
    private let counter: Synchronized<UInt64>

    init(seed: UInt64 = 0) {
        counter = Synchronized(seed)
    }

    func next() -> UUID {
        let value = counter.mutate { current -> UInt64 in
            current += 1
            return current
        }
        return Self.uuid(from: value)
    }

    /// Encodes the counter into the low 8 bytes of a UUID (big-endian); the high
    /// bytes are zero. Deterministic and free of force-unwraps.
    static func uuid(from value: UInt64) -> UUID {
        let bytes = withUnsafeBytes(of: value.bigEndian, Array.init)
        return UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0, 0,
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7]
            ))
    }
}
