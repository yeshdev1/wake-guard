import XCTest

@testable import WakeGuard

/// WG-091: the adversarial **bathroom-return-to-bed** scenario — the classic false-positive trap for
/// movement-based awake detection. The sleeper briefly gets up (a few steps to the bathroom), then
/// returns to bed and is still. This test pins the **conservative, advisory-only** behavior:
///
/// - **Brief movement is conservative.** A few steps (below the recent-steps floor) reaches only
///   `.weak` — one uncorroborated signal, never a corroborated `.likely`; and once the sleeper is back
///   in bed (movement goes stale) the evidence weakens to no prompt — a brief trip doesn't keep
///   looking "awake".
/// - **No automatic cancellation (#8).** Even a substantial-but-brief trip that reads `.likely` (the
///   documented residual — the aggregate movement path can't tell a bathroom trip from a real wake-up
///   walk) carries **no** cancel authority. The strongest outcome is an advisory *prompt*; the alarm is
///   never suppressed, and no response leaves it unchanged (#7).
/// - **Fail-closed sensing.** An unavailable pedometer during the trip declines as `.sourceUnavailable`
///   — "couldn't observe" is never conflated with "confirmed still", and steps reported *while
///   unavailable* still can't nudge.
/// - **Let it ring in the final stretch.** At the imminence cutoff a `.likely` trip does not prompt —
///   critical alarms get the more conservative (120 s) cutoff.
/// - **Documented prompt behavior.** A bathroom trip MAY surface a prompt whose safe default is "keep";
///   turning off a *critical* alarm from it carries the #6 confirmation into the destructive button;
///   and repeated trips in one occurrence are de-duped by the ledger, not by evidence decay.
final class BathroomReturnToBedScenarioTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func evidence(steps: Int, recency: TimeInterval) -> AwakeEvidence {
        AwakeEvidenceModel.evaluate(
            AwakeEvidenceInput(
                recentStepCount: steps, longestEpisodeDuration: 0,
                secondsSinceLastMovement: recency,
                deviceInteracted: false))
    }

    private func makeAlarm() throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(DeterministicIDGenerator(seed: 91).next()), label: "wake",
            schedule: schedule,
            preAlarmPolicy: try PreAlarmPolicy.enabled(
                leadTime: 600, allowedActions: [.turnOffToday, .remindLater]),
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    private func pipeline(
        stepsAt sampleAge: TimeInterval, steps: Int,
        availability: MotionSourceAvailability = .available
    ) -> PreAlarmPipeline {
        let sample = PedometerSample(
            timestamp: now.addingTimeInterval(-sampleAge), quality: .high, stepCount: steps,
            distanceMeters: nil, cadenceStepsPerSecond: nil, secondsSinceLastStep: nil)
        return PreAlarmPipeline(
            movementQuery: RecentMovementQuery(
                source: FakeHistoricalPedometerSource(
                    availabilityState: availability, cannedSamples: [sample])),
            coordinator: PreAlarmPromptCoordinator(ledger: InMemoryPreAlarmPromptLedger()))
    }

    private func evaluate(
        _ evidence: AwakeEvidence, criticality: Criticality, timeRemaining: TimeInterval,
        actions: Set<PreAlarmAction> = [.turnOffToday]
    ) throws -> PreAlarmRecommendation {
        PreAlarmEvaluator.evaluate(
            policy: try PreAlarmPolicy.enabled(leadTime: 600, allowedActions: actions),
            criticality: criticality, timeRemaining: timeRemaining, evidence: evidence)
    }

    // MARK: - Brief movement produces conservative behavior

    func testAFewStepsToTheBathroomIsConservativeNotAwake() {
        // ~8 steps, just now — below the recent-steps floor, so only the recency factor fires: exactly
        // `.weak` (one uncorroborated signal), never a corroborated `.likely`.
        XCTAssertEqual(
            evidence(steps: 8, recency: 60).likelihood, .weak,
            "a few steps is one uncorroborated signal — .weak, not a corroborated 'awake'")
    }

    func testReturnToBedStalesTheEvidenceToConservative() throws {
        // The trip's 20 steps, but 15 minutes ago and the sleeper is back in bed (still): the movement
        // is no longer recent, so only recentSteps fires → `.weak`, and the evaluator declines for weak
        // evidence — asserted by reason, so it can't pass for the wrong reason (e.g. an out-of-window
        // time).
        let stale = evidence(steps: 20, recency: 900)
        XCTAssertEqual(
            stale.likelihood, .weak, "movement 15 min ago isn't 'recent' — only recentSteps")
        let recommendation = try evaluate(stale, criticality: .standard, timeRemaining: 300)
        XCTAssertEqual(recommendation.reason, .insufficientEvidence, "declines for weak evidence")
        XCTAssertFalse(recommendation.shouldPrompt, "back in bed → no prompt")
    }

    // MARK: - No automatic cancellation (#8) — the core safety property

    func testBathroomTripReadsLikelyButNeverAutoCancels() throws {
        // 20 recent steps → the documented residual reads `.likely` (aggregate movement can't tell a
        // bathroom trip from a real wake-up walk). But this is advisory only.
        let trip = evidence(steps: 20, recency: 180)
        XCTAssertEqual(
            trip.likelihood, .likely, "the documented residual: a recent walk reads .likely")
        let recommendation = try evaluate(trip, criticality: .standard, timeRemaining: 300)
        // The strongest outcome is a PROMPT — never a cancellation. The recommendation carries no
        // command/adapter/alarm-id, so a movement inference has no path to suppress the alarm (#8).
        XCTAssertTrue(recommendation.shouldPrompt, "a recent walk may surface an advisory prompt")
        XCTAssertEqual(
            recommendation.offeredActions, [.turnOffToday],
            "the prompt only offers the user's own actions — the user must act; nothing auto-cancels"
        )
    }

    // MARK: - Fail-closed sensing: couldn't-observe is never confirmed-still

    func testUnavailableSensorDuringTripDeclinesAsSourceUnavailable() async throws {
        // Adversarial: a degraded source reports 20 steps *while unavailable*. The evaluator honors
        // `sourceAvailable` explicitly (not the 0-steps coincidence), so steps-while-unavailable still
        // can't nudge, and the reason stays `.sourceUnavailable` — never `.insufficientEvidence`
        // (couldn't observe ≠ confirmed still).
        let blind = RecentMovementSnapshot(
            window: nil, stepCount: 20, secondsSinceLastMovement: 180, sourceAvailable: false)
        let recommendation = PreAlarmEvaluator.evaluate(
            policy: try PreAlarmPolicy.enabled(leadTime: 600, allowedActions: [.turnOffToday]),
            criticality: .standard, timeRemaining: 300, movement: blind)
        XCTAssertEqual(
            recommendation.reason, .sourceUnavailable,
            "couldn't observe → .sourceUnavailable, not .insufficientEvidence")
        XCTAssertFalse(recommendation.shouldPrompt)
        // End-to-end: an unauthorized pedometer during the trip surfaces nothing (fail-closed).
        let content = await pipeline(stepsAt: 60, steps: 20, availability: .notAuthorized).evaluate(
            alarm: try makeAlarm(), occurrence: now.addingTimeInterval(300), timeRemaining: 300,
            deviceInteracted: false, now: now)
        XCTAssertNil(content, "an unavailable sensor never prompts")
    }

    // MARK: - Imminence boundary: let the alarm ring in the final stretch

    func testLikelyTripInTheFinalStretchDoesNotPromptEitherCriticality() throws {
        // A `.likely` trip must NOT prompt at the imminence cutoff (strict `>`): the alarm is about to
        // ring, so a bathroom walk can't nudge it. Critical gets the more conservative cutoff (120 s).
        let trip = evidence(steps: 20, recency: 180)
        let critical = try evaluate(trip, criticality: .critical, timeRemaining: 120)
        XCTAssertEqual(critical.reason, .outsideLeadWindow)
        XCTAssertFalse(critical.shouldPrompt, "a critical alarm is not nudged in its final 120 s")
        let standard = try evaluate(trip, criticality: .standard, timeRemaining: 60)
        XCTAssertFalse(standard.shouldPrompt, "a standard alarm is not nudged in its final 60 s")
    }

    // MARK: - Documented prompt behavior (#6 carried into the button)

    func testTurningOffACriticalAlarmFromTheTripPromptNeedsConfirmation() throws {
        let recommendation = try evaluate(
            evidence(steps: 20, recency: 180), criticality: .critical, timeRemaining: 300)
        XCTAssertTrue(
            recommendation.requiresConfirmation,
            "turning off a critical alarm from a bathroom-trip prompt requires confirmation (#6)")
        // …and that #6 flag is carried into the prompt model: the destructive button confirms, the safe
        // default never does.
        let content = try XCTUnwrap(PreAlarmPromptContent.from(recommendation))
        let turnOff = try XCTUnwrap(content.buttons.first { $0.action == .turnOffToday })
        XCTAssertTrue(
            turnOff.requiresConfirmation, "the destructive button carries the #6 confirmation")
        let keep = try XCTUnwrap(content.buttons.first { $0.action == .keep })
        XCTAssertFalse(keep.requiresConfirmation, "the safe default never confirms")
    }

    // MARK: - End-to-end through the pipeline

    func testTripThroughPipelineSurfacesAPromptWhoseSafeDefaultIsKeep() async throws {
        // The trip (20 steps, a minute ago) surfaces a prompt — but a PROMPT, whose first, safe-default
        // button is "keep": the alarm is unchanged unless the user acts (#7), and the pipeline holds no
        // alarm authority, so nothing is cancelled (#8). This residual is tolerable *because* advisory.
        let content = await pipeline(stepsAt: 60, steps: 20).evaluate(
            alarm: try makeAlarm(), occurrence: now.addingTimeInterval(300), timeRemaining: 300,
            deviceInteracted: false, now: now)
        let buttons = try XCTUnwrap(content, "a recent trip surfaces an advisory prompt").buttons
        XCTAssertEqual(
            buttons.first?.action, .keep, "the prompt's safe default is keep — no auto-cancel")
    }

    func testAstronomicalStepCountStillOnlyPromptsAndNeverTraps() async throws {
        // A degenerate saturated step count (Int.max) still reads `.likely` and must stay advisory — the
        // end-to-end path must not trap and must not gain cancel authority.
        let content = await pipeline(stepsAt: 60, steps: .max).evaluate(
            alarm: try makeAlarm(), occurrence: now.addingTimeInterval(300), timeRemaining: 300,
            deviceInteracted: false, now: now)
        let buttons = try XCTUnwrap(content, "a saturated count still only prompts").buttons
        XCTAssertEqual(
            buttons.first?.action, .keep, "still just a keep-default prompt — never a cancel")
    }

    func testReturnToBedThroughPipelineSurfacesNothing() async throws {
        // The same steps, but 15 min ago (back in bed) — the pipeline surfaces no prompt.
        let content = await pipeline(stepsAt: 900, steps: 20).evaluate(
            alarm: try makeAlarm(), occurrence: now.addingTimeInterval(300), timeRemaining: 300,
            deviceInteracted: false, now: now)
        XCTAssertNil(content, "back in bed (movement stale) → no prompt (conservative)")
    }

    func testRepeatedTripsInOneOccurrenceArePromptedOnlyOnce() async throws {
        // Several bathroom trips a night: within ONE occurrence the per-(alarm, occurrence) ledger — not
        // evidence decay — collapses repeats, so the sleeper is nudged at most once.
        let onePipeline = pipeline(stepsAt: 60, steps: 20)
        let alarm = try makeAlarm()
        let occurrence = now.addingTimeInterval(300)
        let first = await onePipeline.evaluate(
            alarm: alarm, occurrence: occurrence, timeRemaining: 300, deviceInteracted: false,
            now: now)
        XCTAssertNotNil(first, "the first trip surfaces a prompt")
        let second = await onePipeline.evaluate(
            alarm: alarm, occurrence: occurrence, timeRemaining: 300, deviceInteracted: false,
            now: now)
        XCTAssertNil(second, "a second trip in the same occurrence is de-duped, not re-prompted")
    }
}
