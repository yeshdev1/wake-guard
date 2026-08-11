import Foundation
import XCTest

@testable import WakeGuard

/// WG-243: end-to-end anti-shake defense. Drives real observation streams through the
/// `ChallengeObservationReducer` into the `WakeChallengeMachine` and proves that **a shake cannot stop the
/// alarm** (#20) — even when it produces enough pedometer steps — while a **real gait passes** (#19), a
/// **sensor-limited genuine walk still passes** (degraded, not trapped, #21), and a shake **can't bank
/// progress** to be finished with one clean step.
final class ChallengeAntiShakeTests: XCTestCase {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func obs(_ offset: TimeInterval, steps: Int) -> MovementObservation {
        MovementObservation(
            timestamp: Self.base.addingTimeInterval(offset), isMoving: true, cumulativeSteps: steps,
            source: .pedometer)
    }

    private func activeMachine(required: Int = 20) -> WakeChallengeMachine {
        var machine = WakeChallengeMachine(required: required)
        machine.apply(.start)
        machine.apply(.sensorsReady)
        return machine
    }

    private func stream(_ counts: [Int]) -> [MovementObservation] {
        counts.enumerated().map { obs(Double($0.offset), steps: $0.element) }
    }

    /// Feed the reducer over each growing prefix, mirroring the live runtime (observations arrive one at a
    /// time, so the first establishes the baseline and later ones raise the peak).
    private func drive(_ machine: inout WakeChallengeMachine, _ counts: [Int]) {
        for length in 1...counts.count {
            machine.apply(
                ChallengeObservationReducer.event(from: stream(Array(counts.prefix(length)))))
        }
    }

    func testShakeStreamCannotPassEvenWithEnoughSteps() {
        // A bursty shake yields 35 cumulative steps (≥ required 20) but implausibly fast within-burst
        // timing — never `.corroborated`, so the machine never passes.
        var machine = activeMachine()
        drive(&machine, [0, 5, 6, 12, 13, 20, 21, 28, 29, 35])
        XCTAssertNotEqual(machine.phase, .passed, "a shake must never stop the alarm (#20)")
    }

    func testRealGaitStreamPasses() {
        var machine = activeMachine()
        drive(&machine, [0, 2, 4, 7, 9, 11, 14, 16, 18, 20])
        XCTAssertEqual(
            machine.phase, .passed, "a corroborated real walk of the required length passes (#19)")
    }

    func testSensorLimitedWalkNeedsCorroborationNotStepsAlone() {
        // Only two samples ⇒ too few intervals to judge cadence ⇒ `.unavailable`. Progress accumulates but
        // the walk does NOT pass on step count alone — a sensor-limited user takes the accessible
        // alternative (#22), so #20 stays closed and they are never trapped (#21).
        var machine = activeMachine()
        drive(&machine, [0, 20])
        XCTAssertNotEqual(machine.phase, .passed, "a pass requires corroboration, not steps alone")
    }

    func testContradictionZeroesProgressSoAShakeSpliceCannotPass() {
        // Shake to just below the target, then one clean step: the contradiction reset means the clean
        // step can't finish the bar.
        var machine = activeMachine()
        machine.apply(.observedProgress(cumulative: 19, corroboration: .contradicted))
        machine.apply(.observedProgress(cumulative: 20, corroboration: .corroborated))
        XCTAssertNotEqual(machine.phase, .passed, "a shake bar can't be banked then finished")
    }

    func testDirectContradictedProgressNeverPasses() {
        var machine = activeMachine()
        machine.apply(.observedProgress(cumulative: 100, corroboration: .contradicted))
        XCTAssertNotEqual(machine.phase, .passed)
    }
}
