import XCTest

@testable import WakeGuard

/// WG-072: the deterministic accessible (non-walking) alternative runtime. Verifies a debounced tap
/// sequence and a press-and-hold each pass only on deliberate, distinct user input; that rapid /
/// out-of-order / non-finite input can't satisfy them; that thresholds clamp to safe-but-completable
/// bounds; and — the safety core — that the machine advances **only** through explicit input events,
/// so no non-input path (and thus no AI, which can't emit touches) can complete it.
final class AccessibleChallengeTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func taps(_ kind: AccessibleChallenge = .tapSequence, required: Int = 6)
        -> AccessibleChallengeMachine
    {
        AccessibleChallengeMachine(
            AccessibleChallengeRequirements(kind: kind, requiredTaps: required))
    }

    private func hold(duration: TimeInterval = 3) -> AccessibleChallengeMachine {
        AccessibleChallengeMachine(
            AccessibleChallengeRequirements(kind: .pressAndHold, holdDuration: duration))
    }

    // MARK: - Tap sequence

    func testDeliberateTapSequencePasses() {
        var machine = taps(required: 6)
        for index in 0..<6 { machine.tap(at: base.addingTimeInterval(Double(index) * 0.2)) }
        XCTAssertTrue(machine.isPassed)
    }

    func testRapidTapsWithinDebounceAreIgnored() {
        var machine = taps(required: 6)
        // 10 taps in under 0.1 s — a held / auto-repeating touch. Only the first is accepted.
        for index in 0..<10 { machine.tap(at: base.addingTimeInterval(Double(index) * 0.01)) }
        XCTAssertEqual(
            machine.acceptedTaps, 1, "a burst inside the debounce can't rack up the count")
        XCTAssertFalse(machine.isPassed)
    }

    func testSingleTapDoesNotPass() {
        var machine = taps(required: 6)
        XCTAssertTrue(machine.tap(at: base))
        XCTAssertEqual(machine.phase, .inProgress)
        XCTAssertFalse(machine.isPassed)
    }

    func testOutOfOrderTapIgnored() {
        var machine = taps(required: 6)
        XCTAssertTrue(machine.tap(at: base.addingTimeInterval(1.0)))
        XCTAssertFalse(machine.tap(at: base), "a tap timestamped before the last is ignored")
        XCTAssertEqual(machine.acceptedTaps, 1)
    }

    func testTapFractionTracksProgress() {
        var machine = taps(required: 6)
        for index in 0..<3 { machine.tap(at: base.addingTimeInterval(Double(index) * 0.2)) }
        XCTAssertEqual(machine.tapFraction, 0.5)
    }

    func testPassedTapSequenceIsStable() {
        var machine = taps(required: 6)
        for index in 0..<6 { machine.tap(at: base.addingTimeInterval(Double(index) * 0.2)) }
        XCTAssertFalse(machine.tap(at: base.addingTimeInterval(10)), "no more taps after passing")
        XCTAssertEqual(machine.acceptedTaps, 6)
        XCTAssertTrue(machine.isPassed)
    }

    // MARK: - Press and hold

    func testPressAndHoldPassesAfterDuration() {
        var machine = hold(duration: 3)
        machine.beginHold(at: base)
        machine.holdTick(at: base.addingTimeInterval(3))
        XCTAssertTrue(machine.isPassed)
    }

    func testEarlyReleaseResetsHold() {
        var machine = hold(duration: 3)
        machine.beginHold(at: base)
        machine.endHold(at: base.addingTimeInterval(1))
        XCTAssertEqual(machine.phase, .idle, "released before the duration → safe reset")
        XCTAssertFalse(machine.isPassed)
    }

    func testReleaseAfterDurationPasses() {
        var machine = hold(duration: 3)
        machine.beginHold(at: base)
        machine.endHold(at: base.addingTimeInterval(3.5))
        XCTAssertTrue(machine.isPassed)
    }

    func testHoldFractionTracksProgress() {
        var machine = hold(duration: 3)
        machine.beginHold(at: base)
        XCTAssertEqual(machine.holdFraction(at: base.addingTimeInterval(1.5)), 0.5)
    }

    func testAccessibleActivationCompletesHold() {
        var machine = hold(duration: 3)
        machine.completeViaAccessibleActivation()
        XCTAssertTrue(machine.isPassed, "an assistive-tech activation completes the hold")
        var tapMachine = taps()
        tapMachine.completeViaAccessibleActivation()
        XCTAssertEqual(tapMachine.phase, .idle, "no-op for a tap sequence")
    }

    // MARK: - Safe bounds

    func testRequiredTapsClampedToSafeBounds() {
        XCTAssertEqual(
            AccessibleChallengeRequirements(kind: .tapSequence, requiredTaps: 1).requiredTaps, 4)
        XCTAssertEqual(
            AccessibleChallengeRequirements(kind: .tapSequence, requiredTaps: 999).requiredTaps, 12)
    }

    func testHoldDurationClampedToSafeBounds() {
        XCTAssertEqual(
            AccessibleChallengeRequirements(kind: .pressAndHold, holdDuration: 0.5).holdDuration, 2)
        XCTAssertEqual(
            AccessibleChallengeRequirements(kind: .pressAndHold, holdDuration: 100).holdDuration, 8)
        XCTAssertEqual(
            AccessibleChallengeRequirements(kind: .pressAndHold, holdDuration: .nan).holdDuration, 2
        )
    }

    // MARK: - Input-gating (nothing but deliberate input can pass it — so AI can't, #1)

    func testWrongKindEventsAreNoOps() {
        var tapMachine = taps()
        tapMachine.beginHold(at: base)
        tapMachine.holdTick(at: base.addingTimeInterval(100))
        XCTAssertEqual(
            tapMachine.phase, .idle, "hold events do nothing to a tap-sequence challenge")

        var holdMachine = hold()
        XCTAssertFalse(holdMachine.tap(at: base))
        XCTAssertEqual(holdMachine.phase, .idle)
    }

    func testNoAutoPassWithoutDeliberateInput() {
        // A hold tick far in the future with no press, and an untouched tap sequence, both stay idle:
        // the machine only advances on explicit user input — there is no non-input path to `.passed`.
        var holdMachine = hold(duration: 3)
        holdMachine.holdTick(at: base.addingTimeInterval(1_000_000))
        XCTAssertFalse(holdMachine.isPassed)
        XCTAssertEqual(taps().phase, .idle)
    }

    func testNonFiniteTimeIgnored() {
        var machine = taps()
        XCTAssertFalse(machine.tap(at: Date(timeIntervalSince1970: .nan)))
        XCTAssertEqual(machine.phase, .idle)
        var holdMachine = hold()
        holdMachine.beginHold(at: Date(timeIntervalSince1970: .nan))
        XCTAssertEqual(holdMachine.phase, .idle)
    }
}
