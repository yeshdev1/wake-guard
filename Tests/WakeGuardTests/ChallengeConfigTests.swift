import XCTest

@testable import WakeGuard

/// WG-045: wake-challenge configuration. Verifies the domain `.standard` factory fills valid
/// anti-cheat defaults, that `ChallengeDraft` builds/seeds a `ChallengePolicy` and keeps every
/// threshold within the domain's validated bounds (clamping out-of-range input), that a walk
/// challenge always carries an accessible fallback (SCOPE §2.3), and that the create/edit view
/// model threads the configuration into the built alarm.
@MainActor
final class ChallengeConfigTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 45)
    /// 2023-11-14 12:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_699_963_200)

    private func makeVM(editing: Alarm? = nil, _ processor: FakeAlarmCommandProcessor) throws
        -> CreateAlarmViewModel
    {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        return CreateAlarmViewModel(
            editing: editing, processor: processor, clock: TestClock(now: now), ids: ids,
            deviceTimeZone: { zone })
    }

    private func makeAlarm(challenge: ChallengePolicy) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule,
            challengePolicy: challenge, createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    // MARK: - Domain factory

    func testStandardWalkChallengeUsesValidatedDefaults() throws {
        let walk = try WalkChallenge.standard()
        XCTAssertEqual(walk.targetDuration, 10)
        XCTAssertEqual(walk.minimumSteps, 12)
        XCTAssertEqual(walk.maximumCadence, WalkChallenge.defaultMaximumCadence)
        XCTAssertEqual(walk.allowedPauses, WalkChallenge.defaultAllowedPauses)
        XCTAssertEqual(walk.antiCheatThreshold, WalkChallenge.defaultAntiCheatThreshold)
        XCTAssertEqual(walk.accessibleFallback, .tapSequence)
    }

    // MARK: - ChallengeDraft build / seed / bounds

    func testDefaultDraftBuildsNoChallenge() {
        XCTAssertEqual(ChallengeDraft().build(), .none)
    }

    func testWalkDraftBuildsWalkPolicyWithConfiguredFacets() throws {
        var draft = ChallengeDraft()
        draft.kind = .walk
        draft.durationSeconds = 20
        draft.minimumSteps = 25
        draft.accessibleFallback = .pressAndHold

        guard case .walk(let walk) = draft.build() else {
            return XCTFail("a walk draft must build a .walk policy")
        }
        XCTAssertEqual(walk.targetDuration, 20)
        XCTAssertEqual(walk.minimumSteps, 25)
        XCTAssertEqual(walk.accessibleFallback, .pressAndHold)
    }

    func testWalkDraftAlwaysCarriesAnAccessibleFallback() {
        var draft = ChallengeDraft()
        draft.kind = .walk
        XCTAssertNotNil(
            draft.build().accessibleFallback, "SCOPE §2.3: the alternative is always available")
    }

    func testOutOfRangeThresholdsAreClampedWithinValidatedBounds() throws {
        var draft = ChallengeDraft()
        draft.kind = .walk
        draft.durationSeconds = 100_000  // absurd, above the UI bound
        draft.minimumSteps = -5  // below the domain minimum of 1

        guard case .walk(let walk) = draft.build() else { return XCTFail("expected a walk policy") }
        XCTAssertLessThanOrEqual(
            walk.targetDuration, TimeInterval(ChallengeDraft.durationRange.upperBound))
        XCTAssertGreaterThanOrEqual(
            walk.targetDuration, TimeInterval(ChallengeDraft.durationRange.lowerBound))
        XCTAssertLessThanOrEqual(walk.minimumSteps, ChallengeDraft.stepsRange.upperBound)
        XCTAssertGreaterThanOrEqual(walk.minimumSteps, ChallengeDraft.stepsRange.lowerBound)
        XCTAssertGreaterThanOrEqual(walk.minimumSteps, 1, "never below the domain's own bound")
    }

    func testConfiguredWalkCadenceStaysInThePlausibleBand() throws {
        // Across the whole reachable grid, the required cadence (steps ÷ duration) stays in the
        // plausible-walk band — never at/above the anti-cheat cap (unsatisfiable → lockout, a
        // false-fail), nor so low incidental motion passes (false-pass).
        for duration in stride(
            from: ChallengeDraft.durationRange.lowerBound,
            through: ChallengeDraft.durationRange.upperBound, by: 5)
        {
            let bounds = ChallengeDraft.stepsBounds(forDuration: duration)
            for steps in [bounds.lowerBound, bounds.upperBound] {
                var draft = ChallengeDraft()
                draft.kind = .walk
                draft.durationSeconds = duration
                draft.minimumSteps = steps
                guard case .walk(let walk) = draft.build() else {
                    return XCTFail("kind == .walk must build a walk at \(duration)s/\(steps)")
                }
                let cadence = Double(walk.minimumSteps) / walk.targetDuration
                XCTAssertLessThan(
                    cadence, WalkChallenge.defaultMaximumCadence,
                    "\(duration)s/\(steps): required cadence must stay below the anti-cheat cap")
                XCTAssertLessThanOrEqual(cadence, ChallengeDraft.plausibleWalkCadence)
                XCTAssertGreaterThanOrEqual(
                    cadence, ChallengeDraft.minWalkCadence,
                    "\(duration)s/\(steps): too easy — incidental motion would pass")
            }
        }
    }

    func testDegenerateCornersAreClampedToSafeChallenges() throws {
        // The red-team corners: 5s + 50 steps (10 steps/s — unsatisfiable) and 60s + 5 steps
        // (0.08 steps/s — trivial). Both must be pulled into the plausible band.
        var tooHard = ChallengeDraft()
        tooHard.kind = .walk
        tooHard.durationSeconds = 5
        tooHard.minimumSteps = 50
        guard case .walk(let hard) = tooHard.build() else { return XCTFail("expected a walk") }
        XCTAssertLessThan(
            Double(hard.minimumSteps) / hard.targetDuration, WalkChallenge.defaultMaximumCadence,
            "a 5s walk can never require an impossible cadence")

        var tooEasy = ChallengeDraft()
        tooEasy.kind = .walk
        tooEasy.durationSeconds = 60
        tooEasy.minimumSteps = 5
        guard case .walk(let easy) = tooEasy.build() else { return XCTFail("expected a walk") }
        XCTAssertGreaterThanOrEqual(
            Double(easy.minimumSteps) / easy.targetDuration, ChallengeDraft.minWalkCadence,
            "a 60s walk can never be trivially defeatable")
    }

    func testDraftSeedsFromExistingWalkPolicy() throws {
        let walk = try WalkChallenge.standard(
            targetDuration: 30, minimumSteps: 18, accessibleFallback: .pressAndHold)
        let draft = ChallengeDraft(from: .walk(walk))
        XCTAssertEqual(draft.kind, .walk)
        XCTAssertEqual(draft.durationSeconds, 30)
        XCTAssertEqual(draft.minimumSteps, 18)
        XCTAssertEqual(draft.accessibleFallback, .pressAndHold)
    }

    func testDraftSeedsNoneFromNonePolicy() {
        XCTAssertEqual(ChallengeDraft(from: .none).kind, .none)
    }

    // MARK: - View-model integration

    func testCreateThreadsChallengeIntoAlarm() async throws {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeVM(processor)
        vm.challenge.kind = .walk
        vm.challenge.durationSeconds = 15

        _ = await vm.save()

        guard case .create(let alarm) = try XCTUnwrap(processor.seen.first),
            case .walk(let walk) = alarm.challengePolicy
        else { return XCTFail("expected a create carrying a walk challenge") }
        XCTAssertEqual(walk.targetDuration, 15)
        XCTAssertNotNil(walk.accessibleFallback, "a required challenge always has an alternative")
    }

    func testDefaultCreateHasNoChallenge() async throws {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let vm = try makeVM(processor)

        _ = await vm.save()

        guard case .create(let alarm) = try XCTUnwrap(processor.seen.first) else {
            return XCTFail("expected a create")
        }
        XCTAssertEqual(alarm.challengePolicy, .none)
    }

    func testEditSeedsChallengeFromExistingAlarm() throws {
        let walk = try WalkChallenge.standard(targetDuration: 25, minimumSteps: 20)
        let existing = try makeAlarm(challenge: .walk(walk))
        let vm = try makeVM(editing: existing, FakeAlarmCommandProcessor())
        XCTAssertEqual(vm.challenge.kind, .walk)
        XCTAssertEqual(vm.challenge.durationSeconds, 25)
        XCTAssertEqual(vm.challenge.minimumSteps, 20)
    }
}
