import Foundation
import Observation

/// Drives and presents the wake-up math puzzle (WG-308) over the deterministic `WakeMathPuzzleMachine` —
/// the accessible alternative to the walk (#22) and a genuine sleep-inertia breaker. `@MainActor`; the view
/// feeds it typed number-pad input. On a genuine pass it calls `onPassed` — the seam the host wires to the
/// authorized stop (the same one the walk uses). It **reports + relays input**; it never dismisses directly,
/// and there is no AI path to it (#1 — AI can't type the answer any more than it can emit the walk's steps).
@MainActor
@Observable
final class MathPuzzleViewModel {
    private(set) var machine: WakeMathPuzzleMachine
    /// The digits typed so far for the current problem (number-pad entry).
    private(set) var entry = ""
    /// Feedback from the most recent submission — nil until the first submit. Never color-only in the view.
    private(set) var lastResult: MathSubmissionResult?
    /// Called once when the puzzle is solved — wired to the challenge pass / authorized stop (WG-073).
    var onPassed: () -> Void = {}

    /// Answers top out at 29 × 29 = 841, so three digits is the most anyone ever needs.
    static let maxEntryDigits = 3

    init(machine: WakeMathPuzzleMachine) {
        self.machine = machine
    }

    var isPassed: Bool { machine.isPassed }
    var current: WakeMathProblem { machine.current }
    var progressFraction: Double { machine.progressFraction }
    var canSubmit: Bool { !entry.isEmpty && !isPassed }

    // MARK: - User input (the only way it advances)

    func append(_ digit: Int) {
        guard (0...9).contains(digit), entry.count < Self.maxEntryDigits, !isPassed else { return }
        // Ignore a leading zero so the entry stays a plain, unambiguous number.
        if entry.isEmpty, digit == 0 { return }
        entry.append(String(digit))
    }

    func deleteLast() {
        guard !entry.isEmpty else { return }
        entry.removeLast()
    }

    /// Submit the typed answer. Returns the result so the view can speak it. A wrong answer clears the
    /// entry and hands over a fresh problem; the machine never *fails* the alarm (#21).
    @discardableResult
    func submit() -> MathSubmissionResult? {
        guard let answer = Int(entry), !isPassed else { return nil }
        let wasPassed = machine.isPassed
        let result = machine.submit(answer)
        lastResult = result
        entry = ""
        if machine.isPassed, !wasPassed { onPassed() }
        return result
    }

    // MARK: - Display (affirming, short — SleepInertia ≤48 chars, #22)

    var title: String { "Solve to turn off the alarm" }

    var instruction: String { "Type the answer, then tap Enter." }

    /// A plain progress readout — reassuring for a groggy user, and the VoiceOver value for the bar.
    var progressText: String {
        "\(machine.solvedCount) of \(machine.requiredCorrect) solved"
    }

    /// The problem spoken as words so VoiceOver reads "13 times 7" cleanly, not the glyph.
    var problemAccessibilityLabel: String {
        "\(current.multiplicand) times \(current.multiplier)"
    }

    /// Short, non-punishing feedback line — never the only signal (the view pairs it with an icon).
    var feedbackText: String? {
        switch lastResult {
        case .correct: "Correct — one more."
        case .wrong: "Not quite — here's a new one."
        case .passed, .none: nil
        }
    }

    var passedAnnouncement: String { "Correct. Alarm off." }
}
