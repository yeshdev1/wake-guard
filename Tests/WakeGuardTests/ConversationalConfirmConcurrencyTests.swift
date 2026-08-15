import Foundation
import XCTest

@testable import WakeGuard

/// WG-241 regression: a fast double-tap on "Confirm" must commit the proposal **at most once** — the
/// conversational view-model clears its pending intent before the async commit, so a concurrent second
/// `confirm()` can't schedule a duplicate alarm.
@MainActor
final class ConversationalConfirmConcurrencyTests: XCTestCase {

    func testConcurrentConfirmCommitsAtMostOnce() async throws {
        let spy = ConfirmCommitSpy()
        let json = #"""
            {"hour":7,"minute":30,"meridiemSpecified":true,"timeSpecified":true,"weekdays":[],"dayOffset":1}
            """#
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9, minute: 0)))
        let model = ConversationalAlarmViewModel(
            parser: NaturalLanguageAlarmParser(
                generator: StructuredGenerator(
                    provider: ScriptedLanguageModelProvider.returning(json))),
            clock: TestClock(now: now),
            deviceTimeZone: { TimeZone(identifier: "America/New_York") ?? .gmt },
            commit: spy.handler)

        model.input = "wake me at 7:30 tomorrow"
        await model.submit()
        model.answerCritical(false)  // reach the preview through the follow-ups (WG-298)
        model.answerWalk(false)

        // Two confirms fired before the first commit resolves — a double-tap.
        async let first: Void = model.confirm()
        async let second: Void = model.confirm()
        _ = await (first, second)

        XCTAssertEqual(spy.count.get(), 1, "a double-tap must commit at most once")
        XCTAssertEqual(model.stage, .scheduled)
    }
}

private final class ConfirmCommitSpy: Sendable {
    let count = Synchronized(0)
    var handler: @Sendable (ConversationalAlarmSpec) async -> Bool {
        { [count] _ in
            await Task.yield()
            count.mutate { $0 += 1 }
            return true
        }
    }
}
