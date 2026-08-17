import XCTest

@testable import WakeGuard

/// WG-308: the deterministic wake-up math puzzle — the accessible alternative to the walk. Verifies that
/// the seeded problem stream is reproducible and in range; that a correct final answer passes; that a wrong
/// answer never fails the alarm (it hands over a fresh problem and doesn't advance the count); that the
/// required-correct count clamps; and — the safety core — that the machine advances **only** through
/// explicit `submit(_:)` input, so no non-input path (and thus no AI, which can't type) can complete it.
final class WakeMathPuzzleMachineTests: XCTestCase {

    private func machine(required: Int = 2, seed: UInt64 = 0xDEAD_BEEF) -> WakeMathPuzzleMachine {
        WakeMathPuzzleMachine(requiredCorrect: required, seed: seed)
    }

    // MARK: - Deterministic, in-range problem stream

    func testSameSeedYieldsTheSameProblemSequence() {
        var first = machine(seed: 42)
        var second = machine(seed: 42)
        XCTAssertEqual(
            first.current, second.current, "the first problem is a pure function of the seed")
        // Advance both identically (a wrong answer regenerates) — the streams stay in lock-step.
        _ = first.submit(-1)
        _ = second.submit(-1)
        XCTAssertEqual(
            first.current, second.current, "the whole sequence is reproducible from the seed")
    }

    func testProblemsAreAlwaysInTheHarderMultiplicationBand() {
        // Sweep many seeds and many regenerations: every problem is two-digit × two-digit.
        for seed in UInt64(0)..<200 {
            var puzzle = machine(seed: seed)
            for _ in 0..<8 {
                XCTAssertTrue((12...29).contains(puzzle.current.multiplicand))
                XCTAssertTrue((12...29).contains(puzzle.current.multiplier))
                _ = puzzle.submit(-1)  // wrong → next problem
            }
        }
    }

    func testPromptUsesTheTimesSignAndDerivedAnswer() {
        let problem = WakeMathProblem(multiplicand: 23, multiplier: 17)
        XCTAssertEqual(problem.prompt, "23 × 17")
        XCTAssertEqual(problem.answer, 391)
    }

    // MARK: - Passing

    func testTwoCorrectAnswersPass() {
        var puzzle = machine(required: 2)
        XCTAssertEqual(puzzle.submit(puzzle.current.answer), .correct)
        XCTAssertFalse(puzzle.isPassed, "one correct is not enough")
        XCTAssertEqual(puzzle.submit(puzzle.current.answer), .passed)
        XCTAssertTrue(puzzle.isPassed)
        XCTAssertEqual(puzzle.solvedCount, 2)
    }

    func testProgressFractionTracksSolvedOverRequired() {
        var puzzle = machine(required: 2)
        XCTAssertEqual(puzzle.progressFraction, 0)
        _ = puzzle.submit(puzzle.current.answer)
        XCTAssertEqual(puzzle.progressFraction, 0.5, accuracy: 0.0001)
    }

    // MARK: - A wrong answer never fails the alarm (#21)

    func testWrongAnswerHandsOverANewProblemWithoutAdvancing() {
        var puzzle = machine(required: 2)
        let first = puzzle.current
        XCTAssertEqual(puzzle.submit(first.answer + 1), .wrong)
        XCTAssertEqual(puzzle.solvedCount, 0, "a wrong answer never advances the count")
        XCTAssertFalse(puzzle.isPassed, "a wrong answer never fails the alarm — it stays active")
        XCTAssertNotEqual(puzzle.current, first, "a wrong answer hands over a fresh problem")
    }

    func testWrongAnswersCannotAccumulateToAPass() {
        var puzzle = machine(required: 2)
        for _ in 0..<50 { _ = puzzle.submit(-999) }
        XCTAssertFalse(puzzle.isPassed, "no number of wrong answers ever passes")
        XCTAssertEqual(puzzle.solvedCount, 0)
    }

    // MARK: - Clamping and idempotence

    func testRequiredCorrectClampsToSafeBounds() {
        XCTAssertEqual(machine(required: 0).requiredCorrect, 1, "floor is at least one problem")
        XCTAssertEqual(machine(required: 99).requiredCorrect, 5, "ceiling caps the wall of math")
    }

    func testSubmittingAfterPassIsANoOp() {
        var puzzle = machine(required: 1)
        XCTAssertEqual(puzzle.submit(puzzle.current.answer), .passed)
        let afterPass = puzzle
        XCTAssertEqual(puzzle.submit(0), .passed, "post-pass submits are ignored")
        XCTAssertEqual(puzzle, afterPass, "state is unchanged after the pass")
    }
}
