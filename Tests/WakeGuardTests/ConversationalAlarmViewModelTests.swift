import Foundation
import XCTest

@testable import WakeGuard

/// WG-166 / WG-298: the conversational alarm-creation view-model. Verifies the user reaches a **preview**
/// after the schedule parses and the follow-ups (critical / walk / steps+seconds) are gathered — asking
/// only what the text didn't state — that **nothing schedules before an explicit confirm**, that a commit
/// happens **exactly once** carrying the user-confirmed criticality and challenge, and that ambiguity,
/// rejection, model-unavailability, and the **one-tap manual editor** all behave.
@MainActor
final class ConversationalAlarmViewModelTests: XCTestCase {

    /// Counts commits, controls whether scheduling "succeeds", and captures the last committed spec so a
    /// test can assert the confirmed criticality / challenge.
    private final class CommitSpy: Sendable {
        let count = Synchronized(0)
        let succeed = Synchronized(true)
        let lastSpec = Synchronized<ConversationalAlarmSpec?>(nil)
        var handler: @Sendable (ConversationalAlarmSpec) async -> Bool {
            { [count, succeed, lastSpec] spec in
                lastSpec.mutate { $0 = spec }
                count.mutate { $0 += 1 }
                return succeed.get()
            }
        }
    }

    private func fixedNow() throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        return try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9, minute: 0)))
    }

    private func makeModel(
        _ provider: ScriptedLanguageModelProvider, now: Date, commit: CommitSpy
    ) -> ConversationalAlarmViewModel {
        ConversationalAlarmViewModel(
            parser: NaturalLanguageAlarmParser(generator: StructuredGenerator(provider: provider)),
            clock: TestClock(now: now),
            deviceTimeZone: { TimeZone(identifier: "America/New_York") ?? .gmt },
            commit: commit.handler)
    }

    private func model(json: String, now: Date, commit: CommitSpy) -> ConversationalAlarmViewModel {
        makeModel(.returning(json), now: now, commit: commit)
    }

    /// Drive through whatever follow-ups are pending with the given answers, to reach the preview.
    private func answerFollowups(
        _ model: ConversationalAlarmViewModel, critical: Bool = false, walk: Bool = false
    ) {
        if case .askCritical = model.stage { model.answerCritical(critical) }
        if case .askWalk = model.stage { model.answerWalk(walk) }
        if case .configureWalk = model.stage { model.confirmWalkConfiguration() }
    }

    private let futurePreview = #"""
        {"hour":7,"minute":30,"meridiemSpecified":true,"timeSpecified":true,"weekdays":[],"dayOffset":1}
        """#

    // MARK: preview shows schedule + assumptions and schedules nothing

    func testSubmitThenFollowupsReachPreviewWithoutScheduling() async throws {
        let spy = CommitSpy()
        let model = model(json: futurePreview, now: try fixedNow(), commit: spy)
        model.input = "wake me at 7:30 tomorrow"
        await model.submit()
        answerFollowups(model)  // neither critical nor walk stated → answer both "no"

        guard case .preview(let summary) = model.stage else {
            return XCTFail("expected preview, got \(model.stage)")
        }
        XCTAssertEqual(summary.time.hour, 7)
        XCTAssertEqual(summary.time.minute, 30)
        XCTAssertTrue(
            summary.assumptions.contains(.usesCurrentTimeZone(identifier: "America/New_York")))
        XCTAssertTrue(
            summary.assumptions.contains { if case .ringsOn = $0 { true } else { false } })
        XCTAssertTrue(model.canConfirm)
        XCTAssertEqual(spy.count.get(), 0, "nothing may schedule before confirmation")
    }

    func testConfirmSchedulesExactlyOnceAsStandardNoWalk() async throws {
        let spy = CommitSpy()
        let model = model(json: futurePreview, now: try fixedNow(), commit: spy)
        model.input = "wake me at 7:30 tomorrow"
        await model.submit()
        answerFollowups(model, critical: false, walk: false)
        await model.confirm()

        XCTAssertEqual(spy.count.get(), 1)
        XCTAssertEqual(model.stage, .scheduled)
        XCTAssertEqual(spy.lastSpec.get()?.criticality, .standard)
        XCTAssertEqual(spy.lastSpec.get()?.challenge, ChallengePolicy.none)
    }

    func testCommitFailureShowsFailedNotScheduled() async throws {
        let spy = CommitSpy()
        spy.succeed.mutate { $0 = false }
        let model = model(json: futurePreview, now: try fixedNow(), commit: spy)
        model.input = "wake me at 7:30 tomorrow"
        await model.submit()
        answerFollowups(model)
        await model.confirm()

        XCTAssertEqual(spy.count.get(), 1)
        XCTAssertEqual(model.stage, .failed)
    }

    // MARK: follow-ups asked only when not inferred (WG-298)

    func testNeitherMentionedAsksBothQuestionsInOrder() async throws {
        let model = model(json: futurePreview, now: try fixedNow(), commit: CommitSpy())
        model.input = "wake me at 7:30 tomorrow"
        await model.submit()
        XCTAssertEqual(model.stage, .askCritical, "critical wasn't stated, so it's asked first")
        model.answerCritical(false)
        XCTAssertEqual(model.stage, .askWalk, "walk wasn't stated, so it's asked next")
        model.answerWalk(false)
        guard case .preview = model.stage else { return XCTFail("both answered → preview") }
    }

    func testMentioningCriticalPreSetsItAndSkipsThatQuestion() async throws {
        let model = model(json: futurePreview, now: try fixedNow(), commit: CommitSpy())
        model.input = "wake me up at 7:30 tomorrow and make it critical"
        await model.submit()
        // Critical was stated → its question is skipped and pre-set; only walk is asked.
        XCTAssertEqual(model.stage, .askWalk)
        XCTAssertTrue(model.isCritical, "the stated criticality is applied")
        model.answerWalk(false)
        guard case .preview = model.stage else { return XCTFail("expected preview") }
        XCTAssertTrue(model.isCritical)
    }

    func testMentioningWalkSkipsWalkQuestionThenGathersStepsAndSeconds() async throws {
        let model = model(json: futurePreview, now: try fixedNow(), commit: CommitSpy())
        model.input = "wake me at 7:30 tomorrow and make me walk"
        await model.submit()
        // Walk stated → the walk yes/no is skipped, but steps/seconds are still gathered.
        XCTAssertEqual(model.stage, .askCritical, "critical still asked (not stated)")
        model.answerCritical(false)
        XCTAssertEqual(model.stage, .configureWalk, "walk question skipped; configure the walk")
        model.confirmWalkConfiguration()
        guard case .preview = model.stage else { return XCTFail("expected preview") }
        XCTAssertEqual(model.challengeDraft.kind, .walk)
    }

    func testConfirmCarriesCriticalAndWalkIntoTheSpec() async throws {
        let spy = CommitSpy()
        let model = model(json: futurePreview, now: try fixedNow(), commit: spy)
        model.input = "wake me at 7:30 tomorrow"
        await model.submit()
        model.answerCritical(true)
        model.answerWalk(true)
        XCTAssertEqual(model.stage, .configureWalk)
        model.confirmWalkConfiguration()
        await model.confirm()

        XCTAssertEqual(model.stage, .scheduled)
        XCTAssertEqual(spy.lastSpec.get()?.criticality, .critical)
        XCTAssertEqual(spy.lastSpec.get()?.challenge.isRequired, true)
    }

    func testWalkStepsStayWithinCadenceBoundsAfterConfigure() async throws {
        let model = model(json: futurePreview, now: try fixedNow(), commit: CommitSpy())
        model.input = "wake me at 7:30 tomorrow"
        await model.submit()
        model.answerCritical(false)
        model.answerWalk(true)
        model.confirmWalkConfiguration()
        let bounds = ChallengeDraft.stepsBounds(forDuration: model.challengeDraft.durationSeconds)
        XCTAssertTrue(
            bounds.contains(model.challengeDraft.minimumSteps),
            "steps stay in the plausible-cadence band, like the manual editor")
    }

    // MARK: ambiguity → bounded clarification, still nothing scheduled

    func testAmbiguousMeridiemClarifiesThenPreviewsOnChoice() async throws {
        let spy = CommitSpy()
        let json = #"""
            {"hour":8,"minute":0,"meridiemSpecified":false,"timeSpecified":true,"weekdays":[],"dayOffset":1}
            """#
        let model = model(json: json, now: try fixedNow(), commit: spy)
        model.input = "set an alarm for 8"
        await model.submit()

        guard case .clarifying(.meridiem(_, let evening)) = model.stage else {
            return XCTFail("expected meridiem clarification, got \(model.stage)")
        }
        XCTAssertEqual(evening.hour, 20)
        model.choose(evening)
        answerFollowups(model)
        guard case .preview(let summary) = model.stage else { return XCTFail("expected preview") }
        XCTAssertEqual(summary.time.hour, 20)
        XCTAssertEqual(spy.count.get(), 0)
    }

    func testTomorrowWithModelSuppliedWeekdayReachesOneTimePreview() async throws {
        // The WG-296 bug: "wake me at 7 tomorrow" — the model returns BOTH tomorrow's weekday and
        // dayOffset=1, and 7 is meridiem-ambiguous. After choosing a reading and the follow-ups, the flow
        // must reach a one-time preview, never the old "I can't set that repeat pattern" rejection.
        let spy = CommitSpy()
        let json = #"""
            {"hour":7,"minute":0,"meridiemSpecified":false,"timeSpecified":true,"weekdays":["tuesday"],"dayOffset":1}
            """#
        let model = model(json: json, now: try fixedNow(), commit: spy)
        model.input = "wake me at 7 tomorrow"
        await model.submit()

        guard case .clarifying(.meridiem(let morning, _)) = model.stage else {
            return XCTFail("expected meridiem clarification, got \(model.stage)")
        }
        model.choose(morning)
        answerFollowups(model)
        guard case .preview(let summary) = model.stage else {
            return XCTFail("expected a one-time preview, got \(model.stage)")
        }
        XCTAssertEqual(summary.time.hour, 7)
        XCTAssertTrue(
            summary.assumptions.contains { if case .ringsOn = $0 { true } else { false } },
            "a one-time alarm shows a concrete date, not a weekly repeat")
        XCTAssertEqual(spy.count.get(), 0)
    }

    func testMissingTimeAsksForATime() async throws {
        let json = #"""
            {"hour":0,"minute":0,"meridiemSpecified":false,"timeSpecified":false,"weekdays":[],"dayOffset":null}
            """#
        let model = model(json: json, now: try fixedNow(), commit: CommitSpy())
        model.input = "set an alarm for tomorrow"
        await model.submit()
        XCTAssertEqual(model.stage, .clarifying(.missingTime))
    }

    // MARK: rejection and unavailability

    func testPastTimeIsRejected() async throws {
        let json = #"""
            {"hour":8,"minute":0,"meridiemSpecified":true,"timeSpecified":true,"weekdays":[],"dayOffset":0}
            """#
        let model = model(json: json, now: try fixedNow(), commit: CommitSpy())
        model.input = "wake me at 8 today"
        await model.submit()
        XCTAssertEqual(model.stage, .rejected(.inThePast))
    }

    func testUnavailableModelGuidesToSettings() async throws {
        let spy = CommitSpy()
        let model = makeModel(.failing(.unavailable), now: try fixedNow(), commit: spy)
        model.input = "wake me at 7"
        await model.submit()
        XCTAssertEqual(model.stage, .unavailable)
        XCTAssertEqual(spy.count.get(), 0)
    }

    func testReachableButUnusableModelRoutesToNotUnderstood() async throws {
        let spy = CommitSpy()
        let model = makeModel(.failing(.refused), now: try fixedNow(), commit: spy)
        model.input = "wake me at 7"
        await model.submit()
        XCTAssertEqual(model.stage, .notUnderstood)
        XCTAssertEqual(spy.count.get(), 0)
    }

    // MARK: manual editor is one tap away

    func testRequestManualEditorSetsFlag() throws {
        let model = model(json: futurePreview, now: try fixedNow(), commit: CommitSpy())
        XCTAssertFalse(model.manualEditorRequested)
        model.requestManualEditor()
        XCTAssertTrue(model.manualEditorRequested)
    }

    // MARK: summary building (pure)

    func testSummaryCarriesTimeZoneAndWeeklyAssumptions() throws {
        let zone = try IANATimeZone(identifier: "America/New_York")
        let intent = ValidatedAlarmIntent(
            time: try TimeOfDay(hour: 6, minute: 15), recurrence: .weekly([.monday, .friday]),
            timeZone: zone)
        let summary = ParsedScheduleSummary.summary(for: intent)
        XCTAssertEqual(summary.timeZoneIdentifier, "America/New_York")
        XCTAssertTrue(
            summary.assumptions.contains(.usesCurrentTimeZone(identifier: "America/New_York")))
        XCTAssertTrue(summary.assumptions.contains(.repeatsWeekly(days: [.monday, .friday])))
    }
}
