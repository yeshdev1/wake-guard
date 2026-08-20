import Foundation
import XCTest

@testable import WakeGuard

/// WG-319, round twelve: **what the card is allowed to say when it resolves a cold-open spinner.** Split
/// from `ReadinessCardLoadBoundTests` for SwiftLint `file_length`.
///
/// Those tests cover the *mechanism* — that the spinner resolves at all. These cover the *claim*, which is
/// the half review found wrong on a green suite: the first fix resolved the spinner by writing
/// `readiness(from: [])`, which renders three sentences asserting a shortage of the user's data to a reader
/// whose data was never read. The spinner was stuck but honest; resolving it that way made it false.
@MainActor
final class ReadinessColdOpenClaimTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// One night's asleep interval, `dayOffset` days before `base` — enough for a readiness with factors,
    /// so "a good assessment on screen" is a real value and not a sentinel a presence check would flatter.
    private func night(dayOffset: Int, asleepHours: Double = 7) -> [SleepSample] {
        let start = base.addingTimeInterval(Double(dayOffset) * 86_400)
        return [
            SleepSample(
                category: .asleep,
                interval: DateInterval(
                    start: start, end: start.addingTimeInterval(asleepHours * 3_600)))
        ]
    }

    private func twoGoodNights() -> [SleepSample] { night(dayOffset: -1) + night(dayOffset: -2) }

    // MARK: - Resolving the spinner must not fabricate a claim about the user's data

    /// **Round twelve, finding 1.** Resolving the cold-open spinner by writing `readiness(from: [])` buys a
    /// rendered card with three sentences that are all claims about *the user's data*, made from a read that
    /// returned nothing at all. A user with fourteen nights in HealthKit and a hung `HKSampleQuery` is told
    /// their data is missing.
    ///
    /// One assertion per test: `XCTExpectFailure` is satisfied by a single failing assertion, and bundling
    /// these three would let a partial fix go green while the rest of the falsehood ships.
    func testATimedOutColdOpenDoesNotTellTheUserTheyHaveTooLittleSleepData() async throws {
        let sleep = GatedSleepSource()
        let model = ReadinessViewModel(
            sleepQuery: sleep, calendar: makeCalendar(), sleepTimeout: .milliseconds(50))

        let refresh = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(1)
        await refresh.value

        XCTAssertEqual(
            model.readiness, .unavailable(.temporarilyUnavailable),
            """
            nothing was read, so there is no assessment to show — "There isn't enough sleep data yet to \
            estimate how rested you are." is a statement about data the query never looked at
            """)

        await sleep.finish(0, with: [])
    }

    /// The second sentence, and the worse one: an **instruction the reader cannot follow, aimed at a problem
    /// they do not have**. This is the "Pull down to try again" class of defect that WG-318 removed twice —
    /// the sibling path settled it at `MovementUnavailability.temporarilyUnavailable`, whose copy states the
    /// failure and asks the user to change nothing.
    func testATimedOutColdOpenDoesNotInstructTheUserToAddMoreSleepData() async throws {
        let sleep = GatedSleepSource()
        let model = ReadinessViewModel(
            sleepQuery: sleep, calendar: makeCalendar(), sleepTimeout: .milliseconds(50))

        let refresh = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(1)
        await refresh.value

        XCTAssertNotEqual(
            model.assessment.map { ReadinessExplanation.from($0).certaintyNote },
            "Add a few nights of sleep data and this will get more useful.",
            """
            an instruction the reader cannot follow, aimed at a problem they do not have — it sends a user \
            who already has fourteen nights to fix a shortage that does not exist
            """)

        await sleep.finish(0, with: [])
    }

    /// The third sentence — `ReadinessCardView`'s missing-inputs list ("We don't have enough data yet for:
    /// last night's sleep, sleep consistency, recent sleep debt."). It names each factor as individually
    /// absent, which is a strictly more specific falsehood than the summary.
    func testATimedOutColdOpenDoesNotListEveryFactorAsMissing() async throws {
        let sleep = GatedSleepSource()
        let model = ReadinessViewModel(
            sleepQuery: sleep, calendar: makeCalendar(), sleepTimeout: .milliseconds(50))

        let refresh = Task { await model.refresh(now: base) }
        await sleep.waitForQueries(1)
        await refresh.value

        XCTAssertNil(
            model.assessment.map { ReadinessExplanation.from($0).missingInputs },
            "a read that never returned cannot report which factors it was missing")

        await sleep.finish(0, with: [])
    }
}
