import Foundation

/// The wake-challenge form state for the create/edit alarm flow (WG-045). It holds only the
/// user-configurable facets — whether a walk challenge is required, its duration and minimum
/// steps, and the accessible alternative — and builds a validated `ChallengePolicy`. The
/// anti-cheat internals (cadence cap, pause budget, threshold) are not exposed here; they use
/// the domain's validated defaults (`WalkChallenge.standard`), so a configured challenge can
/// never be weakened below the domain's bounds ("thresholds remain within validated bounds").
/// A value type stored on the `@Observable` view model, so the form binds to `challenge.*`.
struct ChallengeDraft: Equatable, Sendable {
    enum Kind: Sendable, CaseIterable, Hashable { case none, walk }

    var kind: Kind = .none
    var durationSeconds: Int = Self.defaultDurationSeconds
    var minimumSteps: Int = Self.defaultMinimumSteps
    /// Always populated, so switching to `.walk` carries an accessible fallback — SCOPE §2.3,
    /// the alternative is always available when a challenge is required (enforced in the domain
    /// by `WalkChallenge` requiring one).
    var accessibleFallback: AccessibleChallenge = .tapSequence

    static let defaultDurationSeconds = 10
    static let defaultMinimumSteps = 12
    /// UI bounds for the two facets. Every produced `WalkChallenge` stays within the domain's
    /// validated bounds (the Steppers bind to these and `build()` clamps defensively).
    static let durationRange = 5...60
    static let stepsRange = 5...50
    /// The required cadence (steps ÷ duration) is held in a plausible-walk band: at most
    /// `plausibleWalkCadence`, kept safely BELOW the anti-cheat `maximumCadence` (4.0 steps/s)
    /// so a legitimate walk can always pass — no unsatisfiable challenge / lockout (false-fail);
    /// at least `minWalkCadence`, so a long window can't be trivialized by incidental motion
    /// (false-pass). This coupling is the config layer's responsibility — the domain validates
    /// each field independently and no other layer guards the ratio (WG-045).
    static let plausibleWalkCadence = 2.0
    static let minWalkCadence = 0.5

    /// The valid `minimumSteps` range for `duration`, coupling the two facets so the required
    /// cadence stays in the plausible-walk band above. Always non-empty and within `stepsRange`.
    static func stepsBounds(forDuration duration: Int) -> ClosedRange<Int> {
        let seconds = Double(duration)
        let lower = max(stepsRange.lowerBound, Int((seconds * minWalkCadence).rounded(.up)))
        let upper = min(stepsRange.upperBound, Int((seconds * plausibleWalkCadence).rounded(.down)))
        return lower...max(lower, upper)
    }

    init() {}

    /// Seed the form from an existing policy for editing.
    init(from policy: ChallengePolicy) {
        switch policy {
        case .none:
            kind = .none
        case .walk(let walk):
            kind = .walk
            let duration = Self.clampDuration(Int(walk.targetDuration.rounded()))
            durationSeconds = duration
            minimumSteps = Self.clampSteps(walk.minimumSteps, forDuration: duration)
            accessibleFallback = walk.accessibleFallback
        }
    }

    /// Pull `minimumSteps` back into the current duration's plausible-walk band. Call after the
    /// duration changes so the on-screen value can't momentarily sit outside the cadence band.
    mutating func normalizeSteps() {
        minimumSteps = Self.clampSteps(minimumSteps, forDuration: durationSeconds)
    }

    /// Build the validated policy. Duration/steps are clamped to the UI bounds and the cadence
    /// band, so `WalkChallenge.standard` never throws; a defensive `nil` (unreachable) degrades
    /// to `.none` rather than force-unwrapping.
    func build() -> ChallengePolicy {
        switch kind {
        case .none:
            return .none
        case .walk:
            let duration = Self.clampDuration(durationSeconds)
            let steps = Self.clampSteps(minimumSteps, forDuration: duration)
            guard
                let walk = try? WalkChallenge.standard(
                    targetDuration: TimeInterval(duration), minimumSteps: steps,
                    accessibleFallback: accessibleFallback)
            else { return .none }
            return .walk(walk)
        }
    }

    private static func clampDuration(_ value: Int) -> Int {
        min(max(value, durationRange.lowerBound), durationRange.upperBound)
    }

    private static func clampSteps(_ value: Int, forDuration duration: Int) -> Int {
        let bounds = stepsBounds(forDuration: duration)
        return min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}
