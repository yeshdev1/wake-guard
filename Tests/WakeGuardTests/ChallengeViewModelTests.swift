import XCTest

@testable import WakeGuard

/// WG-071: the in-progress challenge view model. Verifies that the alarm reads as **active until the
/// challenge passes** (#21), that progress is presented plainly (fraction + "X of Y steps"), that a
/// combined VoiceOver announcement carries the progress, and that haptic cues fire on progress /
/// pass / not-pass. Display logic only — it never dismisses the alarm.
@MainActor
final class ChallengeViewModelTests: XCTestCase {

    private func active(required: Int = 12) -> ChallengeViewModel {
        let viewModel = ChallengeViewModel(required: required)
        viewModel.apply(.start)
        viewModel.apply(.sensorsReady)
        return viewModel
    }

    func testInitialStateIsAlarmActiveWithNoProgress() {
        let viewModel = ChallengeViewModel(required: 12)
        XCTAssertTrue(viewModel.isAlarmActive)
        XCTAssertEqual(viewModel.stepsCompleted, 0)
        XCTAssertEqual(viewModel.progressFraction, 0)
        XCTAssertTrue(viewModel.offersAccessibleAlternative)
        XCTAssertEqual(viewModel.statusLabel, "Preparing")
    }

    func testActiveProgressDisplayAndHaptic() {
        let viewModel = active(required: 12)
        viewModel.apply(.observedProgress(cumulative: 0, corroboration: .corroborated))  // baseline
        viewModel.apply(.observedProgress(cumulative: 6, corroboration: .corroborated))
        XCTAssertEqual(viewModel.progressFraction, 0.5)
        XCTAssertEqual(viewModel.progressText, "6 of 12 steps")
        XCTAssertTrue(viewModel.isAlarmActive)
        XCTAssertEqual(viewModel.statusLabel, "Alarm active")
        XCTAssertEqual(viewModel.headline, "Walk to turn off the alarm")
        XCTAssertEqual(viewModel.lastHapticCue, .progressed)
    }

    func testPassDismissesAlarmWithSuccessHaptic() {
        let viewModel = active(required: 12)
        viewModel.apply(.observedProgress(cumulative: 0, corroboration: .corroborated))
        viewModel.apply(.observedProgress(cumulative: 12, corroboration: .corroborated))
        XCTAssertFalse(viewModel.isAlarmActive, "only a pass dismisses the alarm")
        XCTAssertEqual(viewModel.progressFraction, 1.0)
        XCTAssertEqual(viewModel.statusLabel, "Alarm off")
        XCTAssertEqual(viewModel.headline, "You're up — alarm off")
        XCTAssertFalse(viewModel.offersAccessibleAlternative)
        XCTAssertEqual(viewModel.lastHapticCue, .passed)
    }

    func testBarFullButUnverifiedSaysKeepWalking() {
        // WG-287 stuck-screen finding: the count is complete but the anti-shake gate hasn't
        // corroborated yet — the copy must keep the user walking, never read "0 to go".
        let viewModel = active(required: 12)
        viewModel.apply(.observedProgress(cumulative: 0, corroboration: .unavailable))
        viewModel.apply(.observedProgress(cumulative: 12, corroboration: .unavailable))

        XCTAssertTrue(viewModel.isAlarmActive, "unverified progress never dismisses (#19/#20)")
        XCTAssertTrue(viewModel.isAwaitingVerification)
        XCTAssertTrue(viewModel.instruction.contains("keep walking"), "the copy keeps them moving")
        XCTAssertFalse(viewModel.instruction.contains("0 to go"))
        XCTAssertTrue(viewModel.accessibilityAnnouncement.contains("Keep walking"))

        // Corroboration arrives a moment later → the pass lands and the hint clears.
        viewModel.apply(.observedProgress(cumulative: 12, corroboration: .corroborated))
        XCTAssertFalse(viewModel.isAlarmActive)
        XCTAssertFalse(viewModel.isAwaitingVerification)
    }

    func testTimeoutKeepsAlarmActiveWithWarningHaptic() {
        let viewModel = active()
        viewModel.apply(.timeout)
        XCTAssertTrue(viewModel.isAlarmActive)
        XCTAssertEqual(viewModel.statusLabel, "Time's up")
        XCTAssertTrue(viewModel.offersAccessibleAlternative)
        XCTAssertEqual(viewModel.lastHapticCue, .notPassed)
        XCTAssertTrue(viewModel.instruction.contains("accessible"))
    }

    func testUnavailableKeepsAlarmActiveAndOffersAlternative() {
        let viewModel = ChallengeViewModel(required: 12)
        viewModel.apply(.sensorsUnavailable)
        XCTAssertTrue(viewModel.isAlarmActive)
        XCTAssertEqual(viewModel.statusLabel, "Can't check your walk")
        XCTAssertTrue(viewModel.offersAccessibleAlternative)
        XCTAssertEqual(viewModel.lastHapticCue, .notPassed)
    }

    func testFailedKeepsAlarmActive() {
        let viewModel = active()
        viewModel.apply(.fail)
        XCTAssertTrue(viewModel.isAlarmActive)
        XCTAssertEqual(viewModel.statusLabel, "Interrupted")
        XCTAssertEqual(viewModel.lastHapticCue, .notPassed)
    }

    func testAlarmStaysActiveForEveryNonPassedOutcome() {
        XCTAssertTrue(active().isAlarmActive, "active")

        let timedOut = active()
        timedOut.apply(.timeout)
        XCTAssertTrue(timedOut.isAlarmActive, "timedOut")

        let failed = active()
        failed.apply(.fail)
        XCTAssertTrue(failed.isAlarmActive, "failed")

        let unavailable = ChallengeViewModel(required: 12)
        unavailable.apply(.sensorsUnavailable)
        XCTAssertTrue(unavailable.isAlarmActive, "unavailable")

        let passed = active()
        passed.apply(.observedProgress(cumulative: 0, corroboration: .corroborated))
        passed.apply(.observedProgress(cumulative: 12, corroboration: .corroborated))
        XCTAssertFalse(passed.isAlarmActive, "only passed dismisses")
    }

    func testProgressHapticOnlyFiresWhenProgressAdvances() {
        let viewModel = active(required: 12)
        // baseline — no advance
        viewModel.apply(.observedProgress(cumulative: 0, corroboration: .corroborated))
        XCTAssertNil(viewModel.lastHapticCue, "the baseline observation adds no progress")
        viewModel.apply(.observedProgress(cumulative: 3, corroboration: .corroborated))
        XCTAssertEqual(viewModel.lastHapticCue, .progressed)
    }

    func testAccessibilityAnnouncementCarriesProgress() {
        let viewModel = active(required: 12)
        viewModel.apply(.observedProgress(cumulative: 0, corroboration: .corroborated))
        viewModel.apply(.observedProgress(cumulative: 4, corroboration: .corroborated))
        let announcement = viewModel.accessibilityAnnouncement
        XCTAssertTrue(announcement.contains("Alarm active"))
        XCTAssertTrue(announcement.contains("4 of 12 steps"))
    }
}
