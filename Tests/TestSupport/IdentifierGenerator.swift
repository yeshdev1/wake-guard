import Foundation

@testable import WakeGuard

/// Produces a reproducible sequence of UUIDs from a monotonic counter. The same
/// `seed` always yields the same sequence, so ordering-sensitive tests are stable.
/// The `IdentifierGenerator` port itself is a production type (`AppComposition`),
/// promoted from TestSupport in WG-018.
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
