import Foundation
import Observation

/// Drives and presents the accessible (non-walking) alternative (WG-072) over the deterministic
/// `AccessibleChallengeMachine`. `@MainActor`; the view feeds it user-input events and an injected
/// clock (deterministic in tests). On a genuine completion it calls `onPassed` — the seam the app
/// wires to the authorized stop (WG-073). It **reports + relays input**; it never dismisses directly,
/// and there is no AI path to it (#1).
@MainActor
@Observable
final class AccessibleChallengeViewModel {
    private(set) var machine: AccessibleChallengeMachine
    private let now: @Sendable () -> Date
    /// Called once when the alternative is completed — wired to the challenge pass / authorized stop.
    var onPassed: () -> Void = {}

    init(
        requirements: AccessibleChallengeRequirements,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        machine = AccessibleChallengeMachine(requirements)
        self.now = now
    }

    var kind: AccessibleChallenge { machine.requirements.kind }
    var isPassed: Bool { machine.isPassed }

    var progressFraction: Double {
        kind == .tapSequence ? machine.tapFraction : machine.holdFraction(at: now())
    }

    /// Whether a press-and-hold is currently underway (for the view's live timeline).
    var isHoldInProgress: Bool { kind == .pressAndHold && machine.phase == .inProgress }

    // MARK: - User input (the only way it advances)

    /// Register a tap; returns whether it was accepted (a debounced tap is ignored) so the view can
    /// speak progress only on a real advance.
    @discardableResult
    func tap() -> Bool {
        let wasPassed = machine.isPassed
        let accepted = machine.tap(at: now())
        firePassIfNeeded(wasPassed)
        return accepted
    }

    func beginHold() { machine.beginHold(at: now()) }

    /// Complete a press-and-hold via an assistive-tech activation (VoiceOver / Switch Control) — the
    /// accessible equivalent of a sustained hold, so the fallback is never a dead-end (#21).
    func completeAccessibly() {
        let wasPassed = machine.isPassed
        machine.completeViaAccessibleActivation()
        firePassIfNeeded(wasPassed)
    }

    func holdTick() {
        let wasPassed = machine.isPassed
        machine.holdTick(at: now())
        firePassIfNeeded(wasPassed)
    }

    func endHold() {
        let wasPassed = machine.isPassed
        machine.endHold(at: now())
        firePassIfNeeded(wasPassed)
    }

    private func firePassIfNeeded(_ wasPassed: Bool) {
        if machine.isPassed, !wasPassed { onPassed() }
    }

    // MARK: - Display (non-stigmatizing, affirming — SCOPE §2.3 / #22)

    var title: String { "Another way to turn off the alarm" }

    /// A big, plain live readout — the single most reassuring element for a groggy or low-vision user.
    var progressText: String {
        switch kind {
        case .tapSequence:
            return "\(machine.acceptedTaps) of \(machine.requirements.requiredTaps) taps"
        case .pressAndHold:
            return isPassed ? "Done" : "Keep holding"
        }
    }

    var instruction: String {
        switch kind {
        case .tapSequence:
            return
                "Tap the button \(machine.requirements.requiredTaps) times to turn off the alarm."
        case .pressAndHold:
            return "Press and hold the button until it fills to turn off the alarm."
        }
    }

    /// The VoiceOver announcement for the completion — spoken when passed.
    var passedAnnouncement: String { "Alarm off. Challenge complete." }
}
