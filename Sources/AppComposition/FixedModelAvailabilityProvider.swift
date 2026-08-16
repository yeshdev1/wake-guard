import Foundation

/// A `ModelAvailabilityProviding` that reports a fixed availability (WG-300) — used by the in-memory graph
/// so previews / UI tests are hermetic (they never read the real device's Apple Intelligence state).
/// Defaults to `.deviceNotEligible`, which surfaces the honest "off, using built-in logic" copy **without**
/// the actionable "turn it on" nudge (there's nothing to turn on on an ineligible device), keeping the
/// preview/test surfaces stable.
struct FixedModelAvailabilityProvider: ModelAvailabilityProviding {
    let availability: ModelAvailability

    init(_ availability: ModelAvailability = .unavailable(.deviceNotEligible)) {
        self.availability = availability
    }

    func currentAvailability() -> ModelAvailability { availability }
}
