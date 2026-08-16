import Foundation
import XCTest

@testable import WakeGuard

/// WG-166 / WG-298: the conversational commit converter (`ConversationalAlarmSpec` → `Alarm`) and the
/// fail-closed composition. The converter maps recurrence/time/zone onto a `ScheduleRule` and applies the
/// **user-confirmed** criticality and challenge from the spec — criticality still never comes from the
/// model's output (#31); it comes from the user's explicit choice. Over the hermetic graph (no on-device
/// model), the flow routes to the manual editor (#33).
final class ConversationalAlarmBuilderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func standardSpec(_ intent: ValidatedAlarmIntent) -> ConversationalAlarmSpec {
        ConversationalAlarmSpec(intent: intent, criticality: .standard, challenge: .none)
    }

    func testSpecWithCriticalWalkBuildsACriticalWalkAlarm() throws {
        // WG-298: the user confirmed critical + a walk in the review step — the built alarm carries both.
        let intent = ValidatedAlarmIntent(
            time: try TimeOfDay(hour: 7, minute: 0), recurrence: .weekly([.monday]),
            timeZone: try IANATimeZone(identifier: "America/New_York"))
        var draft = ChallengeDraft()
        draft.kind = .walk
        let spec = ConversationalAlarmSpec(
            intent: intent, criticality: .critical, challenge: draft.build())

        let alarm = try XCTUnwrap(
            ConversationalAlarmBuilder.alarm(from: spec, id: UUID(), now: now))

        XCTAssertEqual(alarm.criticality, .critical, "the user's confirmed criticality is applied")
        XCTAssertTrue(alarm.challengePolicy.isRequired, "the confirmed walk challenge is applied")
        XCTAssertNotNil(
            alarm.challengePolicy.accessibleFallback,
            "a walk always carries a tap alternative (#22)")
    }

    func testWeeklyIntentBuildsStandardWeeklyAlarm() throws {
        let intent = ValidatedAlarmIntent(
            time: try TimeOfDay(hour: 7, minute: 0),
            recurrence: .weekly([.monday, .wednesday, .friday]),
            timeZone: try IANATimeZone(identifier: "America/New_York"))

        let alarm = try XCTUnwrap(
            ConversationalAlarmBuilder.alarm(from: standardSpec(intent), id: UUID(), now: now))

        XCTAssertEqual(alarm.criticality, .standard)
        guard case .weekly(let weekly) = alarm.schedule else {
            return XCTFail("expected a weekly rule")
        }
        XCTAssertEqual(weekly.days.days, [.monday, .wednesday, .friday])
        XCTAssertEqual(weekly.time.hour, 7)
        XCTAssertEqual(weekly.timeZone.identifier, "America/New_York")
    }

    func testOneTimeIntentBuildsStandardOneTimeAlarmOnTheZoneLocalDate() throws {
        let zone = try IANATimeZone(identifier: "America/New_York")
        let fireDate = Date(timeIntervalSince1970: 1_700_050_000)
        let intent = ValidatedAlarmIntent(
            time: try TimeOfDay(hour: 6, minute: 30), recurrence: .oneTime(fireDate: fireDate),
            timeZone: zone)

        let alarm = try XCTUnwrap(
            ConversationalAlarmBuilder.alarm(from: standardSpec(intent), id: UUID(), now: now))

        XCTAssertEqual(alarm.criticality, .standard)
        guard case .oneTime(let oneTime) = alarm.schedule else {
            return XCTFail("expected a one-time rule")
        }
        XCTAssertEqual(oneTime.time.minute, 30)
        XCTAssertEqual(oneTime.timeZone.identifier, "America/New_York")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: fireDate)
        XCTAssertEqual(oneTime.date.year, parts.year)
        XCTAssertEqual(oneTime.date.month, parts.month)
        XCTAssertEqual(
            oneTime.date.day, parts.day, "the one-time date is the fire instant in the zone")
    }

    @MainActor
    func testFlowFailsClosedToManualEditorWhenModelUnavailable() async throws {
        // The hermetic graph's provider reports the model unavailable, so a submit routes to the manual
        // editor rather than fabricating an alarm — the fail-closed path a simulator/ineligible device hits.
        let parser = NaturalLanguageAlarmParser(
            generator: StructuredGenerator(provider: UnavailableLanguageModelProvider()))
        let model = ConversationalAlarmViewModel(
            parser: parser, clock: TestClock(now: now), commit: { _ in true })
        model.input = "wake me at 7am"

        await model.submit()

        guard case .unavailable = model.stage else {
            return XCTFail("an unavailable model must route to the manual editor (#33)")
        }
    }

    @MainActor
    func testScriptedParseCreatesAStandardAlarmThroughTheCommand() async throws {
        // End-to-end over the in-memory graph: a scripted model output parses to a weekly draft, previews,
        // and — only on explicit Confirm — creates a `.standard` alarm through the command boundary.
        let env = try AppEnvironment.inMemory()
        let ids = env.identifierGenerator
        let clock = env.clock
        let processor = env.alarmCommandProcessor
        let json =
            #"{"hour":7,"minute":30,"meridiemSpecified":true,"timeSpecified":true,"#
            + #""weekdays":["monday","tuesday"],"dayOffset":null}"#
        let parser = NaturalLanguageAlarmParser(
            generator: StructuredGenerator(provider: ScriptedLanguageModelProvider.returning(json)))
        let model = ConversationalAlarmViewModel(
            parser: parser, clock: clock,
            deviceTimeZone: { TimeZone(identifier: "America/New_York") ?? .current },
            commit: { spec in
                guard
                    let alarm = ConversationalAlarmBuilder.alarm(
                        from: spec, id: ids.next(), now: clock.now)
                else { return false }
                switch await processor.process(
                    .create(alarm), from: .userInterface, by: .user, userConfirmed: false)
                {
                case .applied, .uncertain: return true
                default: return false
                }
            })

        model.input = "weekdays at 07:30"
        await model.submit()
        // Neither critical nor walk was stated → the flow asks both; answer no to reach the preview.
        model.answerCritical(false)
        model.answerWalk(false)
        guard case .preview = model.stage else {
            return XCTFail("answering the follow-ups should reach the preview; got \(model.stage)")
        }
        await model.confirm()
        guard case .scheduled = model.stage else {
            return XCTFail("Confirm should schedule; got \(model.stage)")
        }

        let alarms = try await env.alarmRepository.allAlarms()
        XCTAssertEqual(alarms.count, 1, "the confirmed conversational alarm is created")
        XCTAssertEqual(
            alarms.first?.criticality, .standard, "created as standard, never critical (#31)")
    }
}
