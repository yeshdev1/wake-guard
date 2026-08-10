import Foundation

/// The user's editable morning-preparation buffers (WG-144) — three **explicit**, named durations that
/// feed the latest-safe-wake calculation (WG-145). It is **pure user configuration**: it needs **no
/// location or calendar permission** — the travel buffer is a user-set default, **not** derived from GPS
/// or a route, and `leadTime` takes only a boolean (does the event have a location), never any location
/// data. Each buffer is clamped to a sane, non-negative range so an edit can't produce an absurd value.
struct MorningPreparationProfile: Sendable, Equatable, Hashable, Codable {
    /// Time to get ready before leaving (shower, dress, breakfast…).
    let preparationBuffer: TimeInterval
    /// Default time to travel to an event that has a location — a user default, never from GPS.
    let travelBuffer: TimeInterval
    /// Extra margin so the user isn't cutting it close.
    let safetyBuffer: TimeInterval

    /// The per-buffer ceiling — generous, but bounds a pathological edit.
    static let maxBuffer: TimeInterval = 6 * 3_600

    static let `default` = MorningPreparationProfile(
        preparationBuffer: 45 * 60, travelBuffer: 30 * 60, safetyBuffer: 10 * 60)

    init(preparationBuffer: TimeInterval, travelBuffer: TimeInterval, safetyBuffer: TimeInterval) {
        self.preparationBuffer = Self.clamp(preparationBuffer)
        self.travelBuffer = Self.clamp(travelBuffer)
        self.safetyBuffer = Self.clamp(safetyBuffer)
    }

    /// The total lead time an event needs before it starts (WG-145): preparation + safety, plus the
    /// travel buffer **only** when the event has a location. Location is a *boolean* — no coordinates, no
    /// permission (#41).
    func leadTime(forEventWithLocation hasLocation: Bool) -> TimeInterval {
        preparationBuffer + (hasLocation ? travelBuffer : 0) + safetyBuffer
    }

    private static func clamp(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), maxBuffer)
    }
}
