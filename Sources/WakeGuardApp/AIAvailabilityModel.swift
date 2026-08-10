import Foundation
import Observation

/// Drives the Settings "On-device intelligence" row (WG-162): reads the current model availability through
/// the injected port, runs it through the pure `AIAvailabilityGate`, and holds the resulting Settings
/// copy for the UI. Recomputed on every `refresh()`, so a change (Apple Intelligence toggled, model
/// finished preparing) replaces any prior value. Holds **no alarm authority** — turning AI on or off here
/// never affects whether an alarm is scheduled or rings (#9).
@MainActor
@Observable
final class AIAvailabilityModel {
    /// The current Settings copy, or `nil` before the first refresh.
    private(set) var status: AIAvailabilityStatusCopy?

    private let provider: any ModelAvailabilityProviding
    private let gate = AIAvailabilityGate()

    init(provider: any ModelAvailabilityProviding) {
        self.provider = provider
    }

    /// The current availability decision (available ⇒ AI on; otherwise the deterministic fallback).
    var decision: AIAvailabilityDecision {
        gate.decide(for: provider.currentAvailability())
    }

    /// Re-read availability and refresh the copy. Total and non-throwing — any unavailable state maps to a
    /// safe "off / preparing" row, never a crash or a blocked screen.
    func refresh() {
        status = AIAvailabilityStatusPresenter.copy(for: decision)
    }
}
