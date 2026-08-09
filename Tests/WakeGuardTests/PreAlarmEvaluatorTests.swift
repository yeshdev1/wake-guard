import XCTest

@testable import WakeGuard

/// WG-082: the pre-alarm evaluator. Verifies it **only recommends whether to prompt** (never cancels,
/// #8), that **criticality and time remaining influence the policy** (the lead window; a critical
/// alarm's confirmation flag + more conservative imminent cutoff, #6), that a single weak signal never
/// prompts (WG-080 floor), and that it ties the WG-081 snapshot through the WG-080 model.
final class PreAlarmEvaluatorTests: XCTestCase {

    private func evidence(_ likelihood: AwakeLikelihood) -> AwakeEvidence {
        switch likelihood {
        case .likely:
            return AwakeEvidenceModel.evaluate(
                AwakeEvidenceInput(
                    recentStepCount: 30, longestEpisodeDuration: 0, secondsSinceLastMovement: 60,
                    deviceInteracted: false))
        case .weak:
            return AwakeEvidenceModel.evaluate(
                AwakeEvidenceInput(
                    recentStepCount: 30, longestEpisodeDuration: 0,
                    secondsSinceLastMovement: .infinity, deviceInteracted: false))
        case .notEnough:
            return AwakeEvidenceModel.evaluate(
                AwakeEvidenceInput(
                    recentStepCount: 0, longestEpisodeDuration: 0,
                    secondsSinceLastMovement: .infinity, deviceInteracted: false))
        }
    }

    private func enabledPolicy(
        leadTime: TimeInterval = 600,
        actions: Set<PreAlarmAction> = [.turnOffToday, .remindLater]
    ) throws -> PreAlarmPolicy {
        try PreAlarmPolicy.enabled(leadTime: leadTime, allowedActions: actions)
    }

    // MARK: - Only recommends whether to prompt

    func testDisabledPolicyNeverPrompts() {
        let rec = PreAlarmEvaluator.evaluate(
            policy: .disabled, criticality: .standard, timeRemaining: 300,
            evidence: evidence(.likely))
        XCTAssertFalse(rec.shouldPrompt)
        XCTAssertEqual(rec.reason, .disabledByPolicy)
    }

    func testPromptsWhenEnabledInWindowAndLikely() throws {
        let policy = try enabledPolicy()
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 300, evidence: evidence(.likely))
        XCTAssertTrue(rec.shouldPrompt)
        XCTAssertEqual(rec.reason, .awakeWithinWindow)
        XCTAssertEqual(rec.offeredActions, [.turnOffToday, .remindLater])
        XCTAssertFalse(rec.requiresConfirmation, "standard alarm — no confirmation flag")
    }

    func testRecommendationOnlyOffersPolicyActionsNeverFabricatesCancel() throws {
        let policy = try enabledPolicy(actions: [.remindLater])
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 300, evidence: evidence(.likely))
        XCTAssertTrue(
            rec.offeredActions.isSubset(of: policy.allowedActions),
            "never offers an action the user didn't allow")
        XCTAssertFalse(rec.offeredActions.contains(.turnOffToday), "a turn-off can't be fabricated")
    }

    func testInformationalPromptWhenNoActions() throws {
        let policy = try enabledPolicy(actions: [])
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 300, evidence: evidence(.likely))
        XCTAssertTrue(rec.shouldPrompt, "an informational prompt still recommends prompting")
        XCTAssertTrue(rec.offeredActions.isEmpty)
    }

    // MARK: - Time remaining influences policy

    func testTooEarlyDoesNotPrompt() throws {
        let policy = try enabledPolicy(leadTime: 600)
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 900, evidence: evidence(.likely))
        XCTAssertEqual(rec.reason, .outsideLeadWindow, "further off than the lead time")
    }

    func testTooImminentDoesNotPrompt() throws {
        let policy = try enabledPolicy(leadTime: 600)
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 30, evidence: evidence(.likely))
        XCTAssertEqual(rec.reason, .outsideLeadWindow, "too close to ringing — let it ring")
    }

    func testNonFiniteAndNegativeTimeRemainingDoNotPrompt() throws {
        let policy = try enabledPolicy(leadTime: 600)
        for timeRemaining in [TimeInterval.nan, .infinity, -100] {
            let rec = PreAlarmEvaluator.evaluate(
                policy: policy, criticality: .standard, timeRemaining: timeRemaining,
                evidence: evidence(.likely))
            XCTAssertEqual(rec.reason, .outsideLeadWindow, "fail-closed for \(timeRemaining)")
        }
    }

    // MARK: - Evidence floor (no single weak signal prompts)

    func testWeakOrInsufficientEvidenceDoesNotPrompt() throws {
        let policy = try enabledPolicy(leadTime: 600)
        for likelihood in [AwakeLikelihood.weak, .notEnough] {
            let rec = PreAlarmEvaluator.evaluate(
                policy: policy, criticality: .standard, timeRemaining: 300,
                evidence: evidence(likelihood))
            XCTAssertEqual(rec.reason, .insufficientEvidence, "\(likelihood) never prompts")
            XCTAssertFalse(rec.shouldPrompt)
        }
    }

    // MARK: - Criticality influences policy

    func testCriticalRequiresConfirmationForDestructiveAction() throws {
        let policy = try enabledPolicy(actions: [.turnOffToday, .remindLater])
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .critical, timeRemaining: 300, evidence: evidence(.likely))
        XCTAssertTrue(rec.shouldPrompt)
        XCTAssertTrue(
            rec.requiresConfirmation, "a critical alarm's turn-off needs confirmation (#6)")
    }

    func testCriticalWithOnlyNonDestructiveActionNeedsNoConfirmation() throws {
        let policy = try enabledPolicy(actions: [.remindLater])
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .critical, timeRemaining: 300, evidence: evidence(.likely))
        XCTAssertTrue(rec.shouldPrompt)
        XCTAssertFalse(rec.requiresConfirmation, "nothing destructive to confirm")
    }

    func testCriticalityTightensTheImminentCutoff() throws {
        let policy = try enabledPolicy(leadTime: 600, actions: [.turnOffToday])
        let standard = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 90, evidence: evidence(.likely))
        let critical = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .critical, timeRemaining: 90, evidence: evidence(.likely))
        XCTAssertTrue(standard.shouldPrompt, "90 s is within the standard window")
        XCTAssertEqual(
            critical.reason, .outsideLeadWindow,
            "a critical alarm isn't nudged this close to ringing")
    }

    // MARK: - Ties WG-081 snapshot through the WG-080 model

    func testConvenienceFromRecentMovementPrompts() throws {
        let policy = try enabledPolicy(actions: [.remindLater])
        let snapshot = RecentMovementSnapshot(
            window: nil, stepCount: 40, secondsSinceLastMovement: 120, sourceAvailable: true)
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 300, movement: snapshot)
        XCTAssertTrue(rec.shouldPrompt)
        XCTAssertTrue(rec.evidence.presentFactors.contains(.recentSteps))
        XCTAssertTrue(rec.evidence.presentFactors.contains(.recentMovement))
    }

    func testConvenienceUnavailableSourceDeclinesAsUnavailable() throws {
        let policy = try enabledPolicy()
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 300, movement: .empty)
        XCTAssertFalse(rec.shouldPrompt, "an unavailable source never nudges")
        XCTAssertEqual(rec.reason, .sourceUnavailable, "couldn't-observe, distinct from still")
    }

    func testUnavailableSourceReportingStepsStillCannotNudge() throws {
        // Robustness: even a (future) degraded source that reports steps while unavailable can't
        // nudge — WG-082 gates on `sourceAvailable`, not the coincidence that unavailable == 0 steps.
        let policy = try enabledPolicy()
        let snapshot = RecentMovementSnapshot(
            window: nil, stepCount: 40, secondsSinceLastMovement: 120, sourceAvailable: false)
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 300, movement: snapshot)
        XCTAssertFalse(rec.shouldPrompt)
        XCTAssertEqual(rec.reason, .sourceUnavailable)
    }

    func testConfirmedStillDeclinesAsInsufficientNotUnavailable() throws {
        // Observed, but no movement — distinct from couldn't-observe: `.insufficientEvidence`.
        let policy = try enabledPolicy()
        let snapshot = RecentMovementSnapshot(
            window: nil, stepCount: 0, secondsSinceLastMovement: .infinity, sourceAvailable: true)
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 300, movement: snapshot)
        XCTAssertFalse(rec.shouldPrompt)
        XCTAssertEqual(rec.reason, .insufficientEvidence)
    }

    func testConvenienceStaleMovementIsWeakAndDoesNotPrompt() throws {
        let policy = try enabledPolicy()
        let snapshot = RecentMovementSnapshot(
            window: nil, stepCount: 40, secondsSinceLastMovement: 1800, sourceAvailable: true)
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 300, movement: snapshot)
        XCTAssertFalse(rec.shouldPrompt, "steps but no recent movement is weak, not likely")
        XCTAssertEqual(rec.reason, .insufficientEvidence)
    }

    /// KNOWN LIMITATION (WG-082, inherited from WG-080): passive transport (a phone accruing steps in
    /// a bag on a moving vehicle) corroborates recent-steps + recency, reads `.likely`, and so
    /// **surfaces a prompt**. Pinned as expected; tolerable only because the prompt is advisory — no
    /// response keeps the alarm (#7) and it never cancels (#8). A cooldown belongs to WG-083.
    func testPassiveTransportStillPromptsKnownLimitation() throws {
        let policy = try enabledPolicy(actions: [.remindLater])
        let transport = RecentMovementSnapshot(
            window: nil, stepCount: 400, secondsSinceLastMovement: 180, sourceAvailable: true)
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 300, movement: transport)
        XCTAssertTrue(rec.shouldPrompt, "advisory nuisance prompt — never a suppression")
    }

    // MARK: - Boundaries and hardened inputs

    func testTimeRemainingAtLeadTimeBoundaryPrompts() throws {
        let policy = try enabledPolicy(leadTime: 600)
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 600, evidence: evidence(.likely))
        XCTAssertTrue(rec.shouldPrompt, "the upper bound is inclusive")
    }

    func testTimeRemainingAtMinimumBoundaryDeclines() throws {
        let policy = try enabledPolicy(leadTime: 600)
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 60, evidence: evidence(.likely))
        XCTAssertEqual(
            rec.reason, .outsideLeadWindow, "the lower bound is strict — 60 s is imminent")
    }

    func testCriticalAtItsMinimumBoundaryDeclines() throws {
        let policy = try enabledPolicy(leadTime: 600)
        let rec = PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .critical, timeRemaining: 120, evidence: evidence(.likely))
        XCTAssertEqual(rec.reason, .outsideLeadWindow, "critical's 120 s cutoff is strict")
    }

    func testEnabledPolicyRejectsNonFiniteLeadTime() {
        XCTAssertThrowsError(try PreAlarmPolicy.enabled(leadTime: .infinity))
        XCTAssertThrowsError(try PreAlarmPolicy.enabled(leadTime: .nan))
    }
}
