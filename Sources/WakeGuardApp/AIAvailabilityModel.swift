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
    /// The current availability decision — **cached**, not recomputed per read (WG-303). The provider's
    /// `currentAvailability()` is a synchronous framework call on the real device (`SystemLanguageModel`),
    /// so reading it inside a SwiftUI `body` on every render hitched the main screen. It's computed once at
    /// init and again only on `refresh()` (view appear / foreground), so the header can read it freely.
    private(set) var decision: AIAvailabilityDecision

    private let provider: any ModelAvailabilityProviding
    private let gate = AIAvailabilityGate()

    init(provider: any ModelAvailabilityProviding) {
        self.provider = provider
        decision = gate.decide(for: provider.currentAvailability())
    }

    /// Re-read availability and refresh the cached decision + copy. Total and non-throwing — any unavailable
    /// state maps to a safe "off / preparing" row, never a crash or a blocked screen. Called on appear and
    /// on foreground, so enabling Apple Intelligence in Settings and returning updates the UI.
    func refresh() {
        decision = gate.decide(for: provider.currentAvailability())
        status = AIAvailabilityStatusPresenter.copy(for: decision)
    }
}
