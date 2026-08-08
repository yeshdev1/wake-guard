import XCTest

@testable import WakeGuard

/// WG-072: the accessible-alternative view model. Verifies a tap sequence and a press-and-hold each
/// complete via user input and fire `onPassed` exactly once, that progress tracks input, and that the
/// copy is affirming (non-stigmatizing).
@MainActor
final class AccessibleChallengeViewModelTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func tapVM(required: Int = 6, clock: MutableClock) -> AccessibleChallengeViewModel {
        AccessibleChallengeViewModel(
            requirements: AccessibleChallengeRequirements(
                kind: .tapSequence, requiredTaps: required),
            now: { clock.now() })
    }

    func testTapSequenceCompletesAndFiresPassedOnce() {
        let clock = MutableClock(base)
        let viewModel = tapVM(clock: clock)
        var passCount = 0
        viewModel.onPassed = { passCount += 1 }
        for _ in 0..<6 {
            viewModel.tap()
            clock.advance(0.2)
        }
        XCTAssertTrue(viewModel.isPassed)
        XCTAssertEqual(passCount, 1, "onPassed fires exactly once on completion")
        viewModel.tap()
        XCTAssertEqual(passCount, 1, "no re-fire after passing")
    }

    func testPressAndHoldCompletesAndFiresPassed() {
        let clock = MutableClock(base)
        let viewModel = AccessibleChallengeViewModel(
            requirements: AccessibleChallengeRequirements(kind: .pressAndHold, holdDuration: 3),
            now: { clock.now() })
        var passed = false
        viewModel.onPassed = { passed = true }
        viewModel.beginHold()
        clock.advance(3)
        viewModel.holdTick()
        XCTAssertTrue(viewModel.isPassed)
        XCTAssertTrue(passed)
    }

    func testCompleteAccessiblyPassesHoldAndFires() {
        let viewModel = AccessibleChallengeViewModel(
            requirements: AccessibleChallengeRequirements(kind: .pressAndHold))
        var passed = false
        viewModel.onPassed = { passed = true }
        viewModel.completeAccessibly()
        XCTAssertTrue(viewModel.isPassed, "an assistive-tech activation completes the hold")
        XCTAssertTrue(passed)
    }

    func testEarlyReleaseDoesNotPass() {
        let clock = MutableClock(base)
        let viewModel = AccessibleChallengeViewModel(
            requirements: AccessibleChallengeRequirements(kind: .pressAndHold, holdDuration: 3),
            now: { clock.now() })
        var passed = false
        viewModel.onPassed = { passed = true }
        viewModel.beginHold()
        clock.advance(1)
        viewModel.endHold()
        XCTAssertFalse(viewModel.isPassed)
        XCTAssertFalse(passed)
    }

    func testTapProgressFraction() {
        let clock = MutableClock(base)
        let viewModel = tapVM(clock: clock)
        for _ in 0..<3 {
            viewModel.tap()
            clock.advance(0.2)
        }
        XCTAssertEqual(viewModel.progressFraction, 0.5)
    }

    func testCopyIsNonStigmatizing() {
        let clock = MutableClock(base)
        let tap = tapVM(clock: clock)
        XCTAssertEqual(tap.title, "Another way to turn off the alarm")
        XCTAssertTrue(tap.instruction.contains("Tap"))
        let hold = AccessibleChallengeViewModel(
            requirements: AccessibleChallengeRequirements(kind: .pressAndHold))
        XCTAssertTrue(hold.instruction.contains("hold"))
    }
}

/// A settable clock for deterministic view-model timing in tests.
private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Date

    init(_ start: Date) { time = start }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return time
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        time = time.addingTimeInterval(interval)
        lock.unlock()
    }
}
