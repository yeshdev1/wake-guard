import XCTest

@testable import WakeGuard

/// WG-090: the persisted, coarse pre-alarm feedback store. Verifies recording folds into an on-device
/// tally, that the tally **persists across store instances** (a relaunch proxy) so feedback is local +
/// durable, that concurrent records don't corrupt the count, that an empty store reads as `.empty`, and
/// — the safety line — that **recording feedback never mutates an alarm** (the store holds no alarm
/// authority, so it cannot silently retune critical behavior; #8/#31).
final class CoreDataPreAlarmFeedbackStoreTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 90)

    func testEmptyStoreReadsAsEmpty() async throws {
        let store = CoreDataPreAlarmFeedbackStore(try PersistenceController(inMemory: true))
        let counts = await store.counts()
        XCTAssertEqual(counts, .empty)
    }

    func testRecordingAggregatesCoarseCounts() async throws {
        let store = CoreDataPreAlarmFeedbackStore(try PersistenceController(inMemory: true))

        await store.record(.notAwake)
        await store.record(.helpful)
        await store.record(.notAwake)

        let counts = await store.counts()
        XCTAssertEqual(counts, PreAlarmFeedbackCounts(notAwakeCount: 2, helpfulCount: 1))
    }

    func testCountsPersistAcrossStoreInstances() async throws {
        let controller = try PersistenceController(inMemory: true)

        await CoreDataPreAlarmFeedbackStore(controller).record(.notAwake)
        await CoreDataPreAlarmFeedbackStore(controller).record(.helpful)
        // A fresh store over the SAME store file — an app-relaunch proxy — sees the folded tally.
        let counts = await CoreDataPreAlarmFeedbackStore(controller).counts()

        XCTAssertEqual(counts, PreAlarmFeedbackCounts(notAwakeCount: 1, helpfulCount: 1))
    }

    func testConcurrentRecordsDoNotCorruptTheStore() async throws {
        let controller = try PersistenceController(inMemory: true)
        // Two independent store actors over the same store race the singleton row — the uniqueness
        // constraint (+ rollback on the losing insert) must never corrupt or duplicate it. Coarse +
        // advisory, so a lost increment under contention is acceptable; the total stays within bounds.
        let storeA = CoreDataPreAlarmFeedbackStore(controller)
        let storeB = CoreDataPreAlarmFeedbackStore(controller)

        async let recordA: Void = storeA.record(.helpful)
        async let recordB: Void = storeB.record(.helpful)
        _ = await (recordA, recordB)

        let counts = await CoreDataPreAlarmFeedbackStore(controller).counts()
        // At least one landed; neither corrupted the row nor duplicated it into a second tally.
        XCTAssertGreaterThanOrEqual(counts.helpfulCount, 1)
        XCTAssertLessThanOrEqual(counts.helpfulCount, 2)
        XCTAssertEqual(counts.notAwakeCount, 0)
    }

    /// The load-bearing safety test: recording feedback **cannot** mutate any alarm. The feedback store
    /// and the alarm repository share the same Core Data stack; recording every feedback category must
    /// leave a saved alarm — and the alarm entity — byte-for-byte unchanged. Feedback has no path to
    /// scheduling or criticality, so it can never silently retune critical behavior (#8/#31).
    func testRecordingFeedbackNeverMutatesAnAlarm() async throws {
        let controller = try PersistenceController(inMemory: true)
        let alarms = CoreDataAlarmRepository(controller)
        let feedback = CoreDataPreAlarmFeedbackStore(controller)

        let alarm = try makeCriticalAlarm()
        try await alarms.save(alarm)
        let before = try await alarms.alarm(id: alarm.id)

        await feedback.record(.notAwake)
        await feedback.record(.helpful)
        await feedback.record(.notAwake)

        let after = try await alarms.alarm(id: alarm.id)
        XCTAssertEqual(after, before, "recording feedback must never change an alarm")
        XCTAssertEqual(after?.criticality, .critical, "criticality is untouched by feedback")
        // And the feedback was still recorded locally — the two concerns are fully independent.
        let counts = await feedback.counts()
        XCTAssertEqual(counts, PreAlarmFeedbackCounts(notAwakeCount: 2, helpfulCount: 1))
    }

    private func makeCriticalAlarm() throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: AlarmID(ids.next()), label: "wake", schedule: schedule, criticality: .critical,
            createdAt: epoch, updatedAt: epoch, revision: 0)
    }
}
