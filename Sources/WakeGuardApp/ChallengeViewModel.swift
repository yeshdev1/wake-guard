import Foundation
import Observation

/// A haptic feedback intent the challenge view plays (WG-071). The view model emits the *intent*
/// (UIKit-free, so it stays testable); the view maps it to a feedback generator. Haptic cues matter
/// most during sleep inertia, when a user may not be reading the screen.
enum ChallengeHapticCue: String, Sendable, Equatable {
    /// Progress advanced — a light encouraging tick.
    case progressed
    /// The challenge passed — success.
    case passed
    /// The challenge ended without passing (timed out / interrupted / unavailable) — a distinct
    /// warning; the alarm is still active.
    case notPassed
}

/// Drives and presents the in-progress wake challenge (WG-071) over the deterministic
/// `WakeChallengeMachine` (WG-068). Foundation-only and `@MainActor`: the runtime feeds it events,
/// and it derives sleep-inertia-friendly display + VoiceOver text + haptic cues. It **reports**, it
/// never dismisses — the alarm stays clearly active until the machine reaches `.passed` (#21).
@MainActor
@Observable
final class ChallengeViewModel {
    private(set) var machine: WakeChallengeMachine
    /// The most recent haptic intent (the view observes this and plays it); `nil` until a cue fires.
    private(set) var lastHapticCue: ChallengeHapticCue?

    init(required: Int) {
        machine = WakeChallengeMachine(required: required)
    }

    // MARK: - Driven by the challenge runtime

    /// Apply a challenge event and emit any resulting haptic cue. Invalid events are no-ops (WG-068).
    func apply(_ event: WakeChallengeEvent) {
        let previousPhase = machine.phase
        let previousCompleted = machine.progress.completed
        machine.apply(event)
        updateHapticCue(previousPhase: previousPhase, previousCompleted: previousCompleted)
    }

    private func updateHapticCue(previousPhase: WakeChallengePhase, previousCompleted: Int) {
        let required = machine.progress.required
        if machine.phase == .passed, previousPhase != .passed {
            lastHapticCue = .passed
        } else if machine.phase.isTerminal, machine.phase != .passed, !previousPhase.isTerminal {
            lastHapticCue = .notPassed
        } else if machine.phase == .active,
            Self.progressMilestone(machine.progress.completed, of: required)
                > Self.progressMilestone(previousCompleted, of: required)
        {
            lastHapticCue = .progressed
        }
    }

    /// Quarter-progress milestone (0…4). Progress haptics fire only on crossing one, so a long walk
    /// doesn't buzz on every step (haptic fatigue) or compete with the alarm's own feedback — while
    /// `.passed` / `.notPassed` stay crisp and rare.
    private static func progressMilestone(_ completed: Int, of required: Int) -> Int {
        guard required > 0 else { return 0 }
        return min(4, (completed * 4) / required)
    }

    // MARK: - Display (all plain values — the view owns the styling)

    /// The alarm is **clearly active until the challenge passes** — only `.passed` dismisses it, so
    /// the view keeps an unmistakable "alarm active" indicator up for every other phase (#21).
    var isAlarmActive: Bool { !machine.phase.permitsAlarmDismissal }

    var progressFraction: Double { machine.progress.fraction }
    var stepsCompleted: Int { machine.progress.completed }
    var stepsRequired: Int { machine.progress.required }
    private var stepsRemaining: Int { max(0, stepsRequired - stepsCompleted) }

    /// A big, plain progress readout — legible during sleep inertia.
    var progressText: String { "\(stepsCompleted) of \(stepsRequired) steps" }

    /// The status shown as text — paired with `statusSystemImage` so meaning is never color-alone.
    var statusLabel: String {
        switch machine.phase {
        case .idle, .starting: return "Preparing"
        case .active: return "Alarm active"
        case .passed: return "Alarm off"
        case .timedOut: return "Time's up"
        case .failed: return "Interrupted"
        case .unavailable: return "Can't check your walk"
        }
    }

    /// An SF Symbol name that conveys the status without color.
    var statusSystemImage: String {
        switch machine.phase {
        case .idle, .starting: return "hourglass"
        case .active: return "alarm.fill"
        case .passed: return "checkmark.circle.fill"
        case .timedOut: return "clock.badge.exclamationmark.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .unavailable: return "sensor.fill"
        }
    }

    /// The large primary line.
    var headline: String {
        switch machine.phase {
        case .idle, .starting: return "Getting ready…"
        case .active: return "Walk to turn off the alarm"
        case .passed: return "You're up — alarm off"
        case .timedOut: return "Still ringing"
        case .failed: return "Challenge interrupted"
        case .unavailable: return "Walk check unavailable"
        }
    }

    /// A short supporting line.
    var instruction: String {
        switch machine.phase {
        case .idle, .starting: return "Hold on a moment."
        case .active:
            return stepsCompleted == 0
                ? "Start walking — \(stepsRequired) steps."
                : "Keep walking — \(stepsRemaining) to go."
        case .passed: return "Nice. Have a good morning."
        case .timedOut, .failed, .unavailable:
            return "The alarm is still active. Use the accessible option to turn it off."
        }
    }

    /// Whether to offer the accessible non-walking alternative — always while the challenge isn't
    /// passed, so a user who can't walk (or whose sensors failed) is never trapped (#21, SCOPE §2.3).
    var offersAccessibleAlternative: Bool { machine.phase != .passed }

    /// A single combined VoiceOver announcement — status, then progress (or outcome).
    var accessibilityAnnouncement: String {
        switch machine.phase {
        case .idle, .starting: return "\(statusLabel). Getting ready."
        case .active: return "Alarm active. \(progressText). Walk to turn off the alarm."
        case .passed: return "Alarm off. Challenge complete."
        case .timedOut, .failed, .unavailable:
            return "\(headline). The alarm is still active. Accessible option available."
        }
    }
}
