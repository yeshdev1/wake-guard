import Foundation

@testable import WakeGuard

/// A `ModelAvailabilityProviding` test double for WG-162: reports a scripted `ModelAvailability` and lets a
/// test **flip** it (Apple Intelligence toggled, model finished preparing) to verify the gate/copy refresh.
final class StubModelAvailabilityProvider: ModelAvailabilityProviding {
    private let state: Synchronized<ModelAvailability>

    init(_ availability: ModelAvailability) {
        state = Synchronized(availability)
    }

    func currentAvailability() -> ModelAvailability { state.get() }

    /// Change the reported availability for the next read.
    func set(_ availability: ModelAvailability) {
        state.mutate { $0 = availability }
    }
}
