import Foundation
import XCTest

@testable import WakeGuard

/// WG-299: the on-device wake-activity history. Verifies the deterministic facts + plain-English fallback,
/// the Core Data store round-trip / ordering / idempotency / prune, that the AI narrator **falls back to
/// the deterministic text** when the model is unavailable and only surfaces **grounded** claims otherwise
/// (#32/#33), the aggregate summary math, and that the challenge runtime **records the right outcome** at
/// a pass / timeout / accessible-fallback.
final class AlarmActivityTests: XCTestCase {

    private let alarmID = AlarmID(DeterministicIDGenerator(seed: 299).next())
    private let at = Date(timeIntervalSince1970: 1_700_000_000)

    private func activity(
        _ outcome: AlarmActivityOutcome, steps: Int = 12, required: Int = 12, seconds: Int = 11,
        walk: Bool = true
    ) -> AlarmActivity {
        AlarmActivity(
            alarmID: alarmID, occurredAt: at, outcome: outcome, walkRequired: walk,
            stepsWalked: steps, requiredSteps: required, durationSeconds: seconds)
    }

    // MARK: deterministic facts + plain-English fallback

    func testPlainSummaryDescribesEachOutcomeInSimpleEnglish() {
        XCTAssertTrue(
            activity(.walkedAndPassed, steps: 14, seconds: 12).plainSummary.contains("14"))
        XCTAssertTrue(
            activity(.walkedAndPassed).plainSummary.lowercased().contains("turned off"))
        XCTAssertTrue(activity(.tapAlternative).plainSummary.lowercased().contains("tap"))
        XCTAssertTrue(
            activity(.timedOut, steps: 5, required: 12).plainSummary.contains("5 of 12"))
        XCTAssertTrue(activity(.interrupted).plainSummary.lowercased().contains("interrupted"))
    }

    func testUnknownStoredOutcomeDecodesToInterrupted() {
        XCTAssertEqual(AlarmActivityOutcome(fromStored: "bogus"), .interrupted)
        XCTAssertEqual(AlarmActivityOutcome(fromStored: "walkedAndPassed"), .walkedAndPassed)
    }

    // MARK: Core Data store round-trip / ordering / idempotency / prune

    func testStoreRecordsAndReadsBackNewestFirst() async throws {
        let store = CoreDataAlarmActivityStore(try PersistenceController(inMemory: true))
        let older = AlarmActivity(
            alarmID: alarmID, occurredAt: at, outcome: .timedOut, walkRequired: true,
            stepsWalked: 3, requiredSteps: 12, durationSeconds: 30)
        let newer = AlarmActivity(
            alarmID: AlarmID(DeterministicIDGenerator(seed: 7).next()),
            occurredAt: at.addingTimeInterval(3600), outcome: .walkedAndPassed, walkRequired: true,
            stepsWalked: 12, requiredSteps: 12, durationSeconds: 10)
        await store.record(AlarmActivityEntry(activity: older, summary: "older"))
        await store.record(AlarmActivityEntry(activity: newer, summary: "newer"))

        let entries = await store.recentActivities(limit: 10)
        XCTAssertEqual(entries.map(\.summary), ["newer", "older"], "newest first")
        XCTAssertEqual(entries.first?.activity.stepsWalked, 12)
        XCTAssertEqual(entries.first?.activity.outcome, .walkedAndPassed)
        XCTAssertEqual(entries.last?.activity.durationSeconds, 30)
    }

    func testStoreIsIdempotentPerOccurrence() async throws {
        let store = CoreDataAlarmActivityStore(try PersistenceController(inMemory: true))
        await store.record(AlarmActivityEntry(activity: activity(.walkedAndPassed), summary: "a"))
        await store.record(AlarmActivityEntry(activity: activity(.walkedAndPassed), summary: "b"))
        let entries = await store.recentActivities(limit: 10)
        XCTAssertEqual(entries.count, 1, "same (alarm, instant) collapses to one row")
        XCTAssertEqual(entries.first?.summary, "a", "the first record wins; a duplicate no-ops")
    }

    func testStorePrunesOldRows() async throws {
        let store = CoreDataAlarmActivityStore(try PersistenceController(inMemory: true))
        await store.record(AlarmActivityEntry(activity: activity(.walkedAndPassed), summary: "old"))
        await store.pruneActivities(olderThan: at.addingTimeInterval(60))
        let entries = await store.recentActivities(limit: 10)
        XCTAssertTrue(entries.isEmpty, "a row older than the cutoff is reaped")
    }

    // MARK: AI narrator — grounded, with deterministic fallback (#32/#33)

    func testNarratorFallsBackToPlainSummaryWhenModelUnavailable() async {
        let narrator = AlarmActivityNarrator(
            generator: ExplanationGenerator(
                generator: StructuredGenerator(
                    provider: ScriptedLanguageModelProvider.failing(.unavailable))))
        let walk = activity(.walkedAndPassed, steps: 14, seconds: 12)
        let text = await narrator.narrate(walk)
        XCTAssertEqual(
            text, walk.plainSummary, "an unavailable model falls back to the deterministic text")
    }

    func testNarratorSurfacesGroundedClaimFromTheModel() async {
        // A grounded claim citing a real activity factor ("outcome") is surfaced verbatim.
        let json = #"{"claims":[{"factorID":"outcome","claim":"You finished the walk — nice."}]}"#
        let narrator = AlarmActivityNarrator(
            generator: ExplanationGenerator(
                generator: StructuredGenerator(
                    provider: ScriptedLanguageModelProvider.returning(json))))
        let text = await narrator.narrate(activity(.walkedAndPassed))
        XCTAssertEqual(text, "You finished the walk — nice.")
    }

    func testNarratorDropsAnUngroundedClaimAndFallsBack() async {
        // A claim citing a factor that isn't part of this activity is dropped; nothing survives → the
        // deterministic fallback is used (the model can't inject a fact that wasn't recorded, #32).
        let json = #"{"claims":[{"factorID":"sleepDebt","claim":"You are exhausted."}]}"#
        let narrator = AlarmActivityNarrator(
            generator: ExplanationGenerator(
                generator: StructuredGenerator(
                    provider: ScriptedLanguageModelProvider.returning(json))))
        let walk = activity(.walkedAndPassed)
        let text = await narrator.narrate(walk)
        XCTAssertEqual(text, walk.plainSummary, "an ungrounded claim never surfaces (#32)")
        XCTAssertFalse(text.lowercased().contains("exhausted"))
    }

    // MARK: aggregate summary math

    func testSummaryAggregatesOutcomesAndAverageSteps() {
        let summary = AlarmActivitySummary([
            activity(.walkedAndPassed, steps: 10), activity(.walkedAndPassed, steps: 20),
            activity(.tapAlternative, walk: false), activity(.timedOut, steps: 4),
        ])
        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.walked, 2)
        XCTAssertEqual(summary.usedTap, 1)
        XCTAssertEqual(summary.missed, 1)
        XCTAssertEqual(summary.averageSteps, 11, "average over walked attempts (10+20+4)/3")
    }

    func testEmptySummaryReadsAsNoWakes() {
        XCTAssertTrue(AlarmActivitySummary([]).plainSummary.lowercased().contains("no wakes"))
    }
}

/// Captures the last recorded activity so a test can assert what the runtime recorded at an outcome.
private final class RecordingActivitySpy: AlarmActivityRecording, @unchecked Sendable {
    private let box = Synchronized<AlarmActivity?>(nil)
    var last: AlarmActivity? { box.get() }
    func record(_ activity: AlarmActivity) async { box.mutate { $0 = activity } }
}

/// WG-299 capture: the challenge runtime records the correct outcome into the activity history.
@MainActor
final class AlarmActivityCaptureTests: XCTestCase {

    private let alarmID = AlarmID(DeterministicIDGenerator(seed: 1).next())
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func samples(_ counts: [Int]) -> [PedometerSample] {
        counts.enumerated().map { index, steps in
            PedometerSample(
                timestamp: base.addingTimeInterval(Double(index)), quality: .high, stepCount: steps)
        }
    }

    private func runtime(
        _ pedometer: any PedometerSource, recorder: RecordingActivitySpy
    ) -> WakeChallengeRuntime {
        let base = base
        return WakeChallengeRuntime(
            alarmID: alarmID, required: 20, pedometer: pedometer,
            processor: FakeAlarmCommandProcessor(), activityRecorder: recorder,
            now: { base })
    }

    func testAPassRecordsWalkedAndPassed() async {
        let spy = RecordingActivitySpy()
        let pedometer = FakePedometerSource(
            availabilityState: .available,
            cannedSamples: samples([0, 2, 4, 7, 9, 11, 14, 16, 18, 20]))
        let runtime = runtime(pedometer, recorder: spy)

        await runtime.drive()
        await runtime.activitySubmission?.value

        XCTAssertEqual(runtime.viewModel.machine.phase, .passed)
        XCTAssertEqual(spy.last?.outcome, .walkedAndPassed)
        XCTAssertEqual(spy.last?.requiredSteps, 20)
        XCTAssertTrue((spy.last?.walkRequired) ?? false)
    }

    func testATimeoutRecordsTimedOut() async {
        let spy = RecordingActivitySpy()
        // Stream ends without reaching 20 steps → timeout.
        let pedometer = FakePedometerSource(
            availabilityState: .available, cannedSamples: samples([0, 2, 4, 6]))
        let runtime = runtime(pedometer, recorder: spy)

        await runtime.drive()
        await runtime.activitySubmission?.value

        XCTAssertEqual(spy.last?.outcome, .timedOut)
    }

    func testAccessibleAlternativeRecordsTapAlternative() async {
        let spy = RecordingActivitySpy()
        let pedometer = FakePedometerSource(availabilityState: .notAuthorized)
        let runtime = runtime(pedometer, recorder: spy)

        await runtime.drive()  // sensors unavailable → offers the fallback
        await runtime.accessibleAlternativePassed()
        await runtime.activitySubmission?.value

        XCTAssertEqual(spy.last?.outcome, .tapAlternative)
    }
}
