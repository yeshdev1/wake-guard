import Foundation

/// A single multiplication problem for the wake-up puzzle (WG-308). Deliberately a *bit* harder than
/// arithmetic that a groggy brain solves reflexively — a two-digit × single-digit product — so solving
/// it takes genuine alertness, without being cruel at 3am. Value type; the answer is derived, never stored.
public struct WakeMathProblem: Sendable, Equatable, Hashable {
    public let multiplicand: Int  // two-digit (11…19)
    public let multiplier: Int  // single-digit (2…9)

    public var answer: Int { multiplicand * multiplier }

    /// Plain "13 × 7" — the × sign (not "x"/"*") reads correctly as "times" in VoiceOver.
    public var prompt: String { "\(multiplicand) × \(multiplier)" }
}

/// The outcome of one answer submission — drives the view's (non-color-only) feedback and speech.
public enum MathSubmissionResult: Sendable, Equatable {
    case correct  // right, but more still required
    case wrong  // wrong — a fresh problem is presented
    case passed  // the final required-correct answer — the challenge is complete
}

/// The deterministic wake-up math puzzle (WG-308) — the accessible alternative to the walk for a user who
/// can't walk or carry the phone (#22), and a genuine sleep-inertia breaker for anyone. It advances **only**
/// through explicit `submit(_:)` calls (number-pad input the user types), reads no clock, and has no model /
/// AI seam — so, exactly as AI cannot emit touches to pass the walk (#1), **AI can neither pose nor solve
/// it on the user's behalf**. Like every challenge it only ever reaches passed; a wrong answer never *fails*
/// the alarm — it simply hands over a new problem, so the fallback is never a dead-end (#21).
///
/// Pure value type: problems come from a self-contained SplitMix64 stream seeded at init, so a given seed
/// yields a fully reproducible sequence — deterministic and exhaustively testable, no closures to inject.
public struct WakeMathPuzzleMachine: Sendable, Equatable {
    public let requiredCorrect: Int
    public private(set) var solvedCount: Int
    public private(set) var attempts: Int
    public private(set) var current: WakeMathProblem
    public private(set) var isPassed: Bool
    private var rngState: UInt64

    /// Clamp so the puzzle is always a *deliberate* wake task: at least one problem, capped so a groggy
    /// user is never trapped behind an endless wall of arithmetic. Default 2 (WG-308: "2 and a bit harder").
    public static let requiredCorrectFloor = 1
    public static let requiredCorrectCeiling = 5

    public init(requiredCorrect: Int = 2, seed: UInt64) {
        self.requiredCorrect = min(
            Self.requiredCorrectCeiling, max(Self.requiredCorrectFloor, requiredCorrect))
        solvedCount = 0
        attempts = 0
        isPassed = false
        var state = seed
        current = Self.makeProblem(&state)
        rngState = state
    }

    /// Progress toward the required count (0…1) — for the view's bar and VoiceOver value.
    public var progressFraction: Double {
        min(1, Double(solvedCount) / Double(requiredCorrect))
    }

    /// Submit a typed answer. A correct-but-not-final answer advances the count and hands over a fresh
    /// problem; the final correct answer passes; a wrong answer hands over a fresh problem and never
    /// advances the count (so brute-forcing one problem is pointless — each wrong try is a *new* problem).
    @discardableResult
    public mutating func submit(_ answer: Int) -> MathSubmissionResult {
        guard !isPassed else { return .passed }
        attempts += 1
        let wasCorrect = answer == current.answer
        if wasCorrect {
            solvedCount += 1
            if solvedCount >= requiredCorrect {
                isPassed = true
                return .passed
            }
        }
        current = Self.makeProblem(&rngState)
        return wasCorrect ? .correct : .wrong
    }

    // MARK: - Deterministic problem stream (SplitMix64)

    private static func nextRandom(_ state: inout UInt64) -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mix = state
        mix = (mix ^ (mix >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mix = (mix ^ (mix >> 27)) &* 0x94D0_49BB_1331_11EB
        return mix ^ (mix >> 31)
    }

    private static func makeProblem(_ state: inout UInt64) -> WakeMathProblem {
        let multiplicand = Int(nextRandom(&state) % 9) + 11  // 11…19
        let multiplier = Int(nextRandom(&state) % 8) + 2  // 2…9
        return WakeMathProblem(multiplicand: multiplicand, multiplier: multiplier)
    }
}
