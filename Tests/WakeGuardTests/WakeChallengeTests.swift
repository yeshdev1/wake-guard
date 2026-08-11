import XCTest

@testable import WakeGuard

/// WG-068: the deterministic wake-challenge state machine. Verifies the happy path to `.passed`,
/// that progress is monotonic (peak-based) and **inflation-proof** against replayed / reset-spammed /
/// overflowing cumulative counts, that a pause safely resets, that only valid transitions change
/// state (invalid events are no-ops), and — the safety core — that every terminal phase except
/// `.passed` keeps the alarm active (#21).
final class WakeChallengeTests: XCTestCase {

    private func started(required: Int = 20) -> WakeChallengeMachine {
        var machine = WakeChallengeMachine(required: required)
        XCTAssertTrue(machine.apply(.start))
        XCTAssertTrue(machine.apply(.sensorsReady))
        XCTAssertEqual(machine.phase, .active)
        return machine
    }

    // MARK: - Happy path + progress

    func testInitialStateIsIdle() {
        let machine = WakeChallengeMachine(required: 20)
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.progress.completed, 0)
    }

    func testHappyPathReachesPassedAndPermitsDismissal() {
        var machine = started(required: 20)
        machine.apply(.observedProgress(cumulative: 0, corroboration: .corroborated))  // baseline
        XCTAssertTrue(
            machine.apply(.observedProgress(cumulative: 20, corroboration: .corroborated)))
        XCTAssertEqual(machine.phase, .passed)
        XCTAssertTrue(machine.progress.isComplete)
        XCTAssertTrue(machine.phase.permitsAlarmDismissal)
    }

    func testProgressIsMonotonicViaPeak() {
        var machine = started(required: 20)
        machine.apply(.observedProgress(cumulative: 0, corroboration: .corroborated))  // baseline 0
        // peak 8 -> completed 8
        machine.apply(.observedProgress(cumulative: 8, corroboration: .corroborated))
        // dip ignored — peak stays 8
        machine.apply(.observedProgress(cumulative: 3, corroboration: .corroborated))
        XCTAssertEqual(machine.progress.completed, 8, "a lower count never retreats progress")
        // peak 103 -> clamp 20 -> pass
        machine.apply(.observedProgress(cumulative: 103, corroboration: .corroborated))
        XCTAssertEqual(machine.progress.completed, 20)
        XCTAssertEqual(machine.phase, .passed)
    }

    func testReplayedCumulativeCannotInflate() {
        var machine = started(required: 20)
        for cumulative in [0, 10, 10, 10] {
            machine.apply(.observedProgress(cumulative: cumulative, corroboration: .corroborated))
        }
        XCTAssertEqual(machine.progress.completed, 10, "replaying a value can't raise the peak")
        XCTAssertEqual(machine.phase, .active)
    }

    func testResetSpamCannotInflate() {
        var machine = started(required: 20)
        // A counter reset (dip) followed by re-climbing the same range must not add each time.
        for cumulative in [0, 10, 0, 10, 0, 10] {
            machine.apply(.observedProgress(cumulative: cumulative, corroboration: .corroborated))
        }
        XCTAssertEqual(
            machine.progress.completed, 10, "reset-spam can't inflate past the real peak")
        XCTAssertEqual(machine.phase, .active)
    }

    func testHugeCumulativeSaturatesWithoutTrapping() {
        var machine = started(required: 20)
        machine.apply(.observedProgress(cumulative: 100, corroboration: .corroborated))  // baseline
        XCTAssertTrue(
            machine.apply(.observedProgress(cumulative: Int.max, corroboration: .corroborated)))
        XCTAssertEqual(machine.progress.completed, 20, "an implausible span saturates, never traps")
        XCTAssertEqual(machine.phase, .passed)
    }

    func testPauseSafelyResetsProgressButStaysActive() {
        var machine = started(required: 20)
        machine.apply(.observedProgress(cumulative: 0, corroboration: .corroborated))
        machine.apply(.observedProgress(cumulative: 12, corroboration: .corroborated))
        XCTAssertTrue(machine.apply(.pause))
        XCTAssertEqual(machine.progress.completed, 0, "a pause safely resets progress to zero")
        XCTAssertEqual(machine.phase, .active, "a pause does not end the challenge")
    }

    // MARK: - Non-pass terminals keep the alarm active (#21)

    func testTimeoutKeepsAlarmActive() {
        var machine = started()
        XCTAssertTrue(machine.apply(.timeout))
        XCTAssertEqual(machine.phase, .timedOut)
        XCTAssertFalse(machine.phase.permitsAlarmDismissal)
    }

    func testTimeoutFromStarting() {
        var machine = WakeChallengeMachine(required: 20)
        machine.apply(.start)
        XCTAssertTrue(machine.apply(.timeout))
        XCTAssertEqual(machine.phase, .timedOut)
    }

    func testFailKeepsAlarmActive() {
        var machine = started()
        XCTAssertTrue(machine.apply(.fail))
        XCTAssertEqual(machine.phase, .failed)
        XCTAssertFalse(machine.phase.permitsAlarmDismissal)
    }

    func testUnavailableFromIdleStartingAndActive() {
        var fromIdle = WakeChallengeMachine(required: 20)
        XCTAssertTrue(fromIdle.apply(.sensorsUnavailable))
        XCTAssertEqual(fromIdle.phase, .unavailable)

        var fromStarting = WakeChallengeMachine(required: 20)
        fromStarting.apply(.start)
        XCTAssertTrue(fromStarting.apply(.sensorsUnavailable))
        XCTAssertEqual(fromStarting.phase, .unavailable)

        var fromActive = started()
        XCTAssertTrue(fromActive.apply(.sensorsUnavailable))
        XCTAssertEqual(fromActive.phase, .unavailable)
        XCTAssertFalse(fromActive.phase.permitsAlarmDismissal)
    }

    // MARK: - Reset / terminal stability

    func testResetFromEachTerminalReturnsToIdle() {
        for terminalEvent in [WakeChallengeEvent.timeout, .fail, .sensorsUnavailable] {
            var machine = started(required: 20)
            machine.apply(.observedProgress(cumulative: 0, corroboration: .corroborated))
            machine.apply(.observedProgress(cumulative: 5, corroboration: .corroborated))
            machine.apply(terminalEvent)
            XCTAssertTrue(machine.phase.isTerminal)
            XCTAssertTrue(machine.apply(.reset))
            XCTAssertEqual(machine.phase, .idle)
            XCTAssertEqual(machine.progress.completed, 0, "reset clears progress")
        }
    }

    func testPassedIsStableAgainstFurtherEvents() {
        var machine = started(required: 5)
        machine.apply(.observedProgress(cumulative: 0, corroboration: .corroborated))
        machine.apply(.observedProgress(cumulative: 5, corroboration: .corroborated))
        XCTAssertEqual(machine.phase, .passed)
        XCTAssertFalse(
            machine.apply(.observedProgress(cumulative: 99, corroboration: .corroborated)),
            "no progress after passing")
        XCTAssertFalse(machine.apply(.start), "cannot restart a passed challenge without reset")
        XCTAssertEqual(machine.phase, .passed)
    }

    // MARK: - Only valid transitions

    func testInvalidTransitionsAreNoOps() {
        var machine = WakeChallengeMachine(required: 10)
        XCTAssertFalse(
            machine.apply(.observedProgress(cumulative: 5, corroboration: .corroborated)),
            "no progress while idle")
        XCTAssertFalse(machine.apply(.sensorsReady), "cannot become active without starting")
        XCTAssertFalse(machine.apply(.pause), "nothing to pause while idle")
        XCTAssertFalse(machine.apply(.reset), "idle is not terminal")
        XCTAssertEqual(machine.phase, .idle, "invalid events never change state")

        machine = started()
        XCTAssertFalse(machine.apply(.start), "cannot re-start an active challenge")
        XCTAssertFalse(machine.apply(.sensorsReady), "already active")
        XCTAssertEqual(machine.phase, .active)
    }

    // MARK: - Phase properties

    func testPermitsAlarmDismissalOnlyForPassed() {
        for phase in WakeChallengePhase.allCases {
            XCTAssertEqual(phase.permitsAlarmDismissal, phase == .passed, "\(phase) dismissal")
        }
    }

    func testTerminalPhases() {
        let terminals: Set<WakeChallengePhase> = [.passed, .failed, .timedOut, .unavailable]
        for phase in WakeChallengePhase.allCases {
            XCTAssertEqual(phase.isTerminal, terminals.contains(phase), "\(phase) terminality")
        }
    }

    // MARK: - Progress value semantics

    func testChallengeProgressBaselineClampAndReset() {
        var progress = ChallengeProgress(required: 0)
        XCTAssertEqual(progress.required, 1, "a zero target is clamped so it can't auto-pass")
        XCTAssertFalse(progress.isComplete)
        progress.observe(cumulative: 5)  // baseline — no progress yet
        XCTAssertEqual(progress.completed, 0, "the first observation only sets the baseline")
        progress.observe(cumulative: 4)  // below baseline/peak — ignored
        XCTAssertEqual(progress.completed, 0)
        progress.observe(cumulative: 6)  // peak 6 -> +1 -> complete (required 1)
        XCTAssertEqual(progress.completed, 1)
        XCTAssertTrue(progress.isComplete)
        progress.reset()
        XCTAssertEqual(progress.completed, 0)
    }

    func testChallengeProgressSpanOverflowSaturates() {
        var progress = ChallengeProgress(required: 100)
        progress.observe(cumulative: .min)  // baseline Int.min
        progress.observe(cumulative: .max)  // peak Int.max — span overflows -> saturate, no trap
        XCTAssertEqual(progress.completed, 100)
        XCTAssertTrue(progress.isComplete)
    }
}
