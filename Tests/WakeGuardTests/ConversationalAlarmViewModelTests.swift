import Foundation
import XCTest

@testable import WakeGuard

/// WG-166: the conversational alarm-creation view-model. Verifies the user reaches a **preview of the
/// parsed schedule and its assumptions**, that **nothing schedules before an explicit confirm**, that a
/// commit happens **exactly once** on confirm, and that ambiguity, rejection, model-unavailability, and
/// the **one-tap manual editor** all behave.
@MainActor
final class ConversationalAlarmViewModelTests: XCTestCase {

    /// Counts commits and controls whether scheduling "succeeds", so tests can assert nothing schedules
    /// before confirmation.
    private final class CommitSpy: Sendable {
        let count = Synchronized(0)
        let succeed = Synchronized(true)
        var handler: @Sendable (ValidatedAlarmIntent) async -> Bool {
            { [count, succeed] _ in
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

    private let futurePreview = #"""
        {"hour":7,"minute":30,"meridiemSpecified":true,"timeSpecified":true,"weekdays":[],"dayOffset":1}
        """#

    // MARK: preview shows schedule + assumptions and schedules nothing

    func testSubmitReachesPreviewWithoutScheduling() async throws {
        let spy = CommitSpy()
        let model = model(json: futurePreview, now: try fixedNow(), commit: spy)
        model.input = "wake me at 7:30 tomorrow"
        await model.submit()

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

    func testConfirmSchedulesExactlyOnce() async throws {
        let spy = CommitSpy()
        let model = model(json: futurePreview, now: try fixedNow(), commit: spy)
        model.input = "wake me at 7:30 tomorrow"
        await model.submit()
        await model.confirm()

        XCTAssertEqual(spy.count.get(), 1)
        XCTAssertEqual(model.stage, .scheduled)
    }

    func testCommitFailureShowsFailedNotScheduled() async throws {
        let spy = CommitSpy()
        spy.succeed.mutate { $0 = false }
        let model = model(json: futurePreview, now: try fixedNow(), commit: spy)
        model.input = "wake me at 7:30 tomorrow"
        await model.submit()
        await model.confirm()

        XCTAssertEqual(spy.count.get(), 1)
        XCTAssertEqual(model.stage, .failed)
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
        guard case .preview(let summary) = model.stage else { return XCTFail("expected preview") }
        XCTAssertEqual(summary.time.hour, 20)
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

    func testModelUnavailableRoutesToManualFallback() async throws {
        let spy = CommitSpy()
        let model = makeModel(.failing(.refused), now: try fixedNow(), commit: spy)
        model.input = "wake me at 7"
        await model.submit()
        XCTAssertEqual(model.stage, .unavailable)
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
