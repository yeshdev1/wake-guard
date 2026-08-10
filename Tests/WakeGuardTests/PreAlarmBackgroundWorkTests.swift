import XCTest

@testable import WakeGuard

/// Runs-on-a-phone step 6: the pre-alarm evaluation work (the foreground-fallback / background
/// opportunity `work`). Verifies it posts the advisory prompt for an alarm inside its lead window when
/// the pipeline recommends one, **de-dups** a second pass, posts nothing outside the window / when the
/// pre-alarm policy is off / when the repo is unreadable (fail-safe), and never touches an alarm.
final class PreAlarmBackgroundWorkTests: XCTestCase {

    private func iso(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func makeRepo() throws -> CoreDataAlarmRepository {
        CoreDataAlarmRepository(try PersistenceController(inMemory: true))
    }

    private func makeAlarm(preAlarmEnabled: Bool = true) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        let policy =
            preAlarmEnabled
            ? try PreAlarmPolicy.enabled(
                leadTime: 600, allowedActions: [.turnOffToday, .remindLater])
            : PreAlarmPolicy.disabled
        return try Alarm(
            id: AlarmID(DeterministicIDGenerator(seed: 6).next()), label: "wake",
            schedule: schedule,
            preAlarmPolicy: policy, createdAt: epoch, updatedAt: epoch, revision: 0)
    }

    private func makeWork(
        repo: any AlarmRepository, now: Date, steps: Int,
        scheduler: InMemoryPreAlarmNotificationScheduler
    ) -> PreAlarmBackgroundWork {
        let sample = PedometerSample(
            timestamp: now.addingTimeInterval(-60), quality: .high, stepCount: steps,
            distanceMeters: nil, cadenceStepsPerSecond: nil, secondsSinceLastStep: nil)
        let pipeline = PreAlarmPipeline(
            movementQuery: RecentMovementQuery(
                source: FakeHistoricalPedometerSource(cannedSamples: [sample])),
            coordinator: PreAlarmPromptCoordinator(ledger: InMemoryPreAlarmPromptLedger()))
        return PreAlarmBackgroundWork(
            alarms: repo, pipeline: pipeline, notifications: scheduler, deviceTimeZone: { .gmt })
    }

    func testPostsThePromptForAnAlarmInTheLeadWindow() async throws {
        let repo = try makeRepo()
        let alarm = try makeAlarm()
        try await repo.save(alarm)
        let now = try iso("2026-08-17T06:55:00Z")  // 5 min before a 07:00 alarm, lead 10 min
        let scheduler = InMemoryPreAlarmNotificationScheduler()
        await makeWork(repo: repo, now: now, steps: 20, scheduler: scheduler).run(now: now)
        XCTAssertEqual(scheduler.posts.count, 1, "a recent walk in the lead window posts a prompt")
        XCTAssertEqual(scheduler.posts.first?.context.alarmID, alarm.id)
        XCTAssertEqual(scheduler.posts.first?.context.remindersUsed, 0, "the initial prompt")
    }

    func testDeDupsASecondPassForTheSameOccurrence() async throws {
        let repo = try makeRepo()
        try await repo.save(makeAlarm())
        let now = try iso("2026-08-17T06:55:00Z")
        let scheduler = InMemoryPreAlarmNotificationScheduler()
        let work = makeWork(repo: repo, now: now, steps: 20, scheduler: scheduler)
        await work.run(now: now)
        await work.run(now: now)
        XCTAssertEqual(scheduler.posts.count, 1, "the same occurrence is not prompted twice")
    }

    func testPostsNothingOutsideTheLeadWindow() async throws {
        let repo = try makeRepo()
        try await repo.save(makeAlarm())
        let now = try iso("2026-08-17T05:00:00Z")  // 2h before → outside the 10-min lead window
        let scheduler = InMemoryPreAlarmNotificationScheduler()
        await makeWork(repo: repo, now: now, steps: 20, scheduler: scheduler).run(now: now)
        XCTAssertTrue(scheduler.posts.isEmpty, "no prompt outside the lead window")
    }

    func testDisabledPreAlarmPolicyPostsNothing() async throws {
        let repo = try makeRepo()
        try await repo.save(makeAlarm(preAlarmEnabled: false))
        let now = try iso("2026-08-17T06:55:00Z")
        let scheduler = InMemoryPreAlarmNotificationScheduler()
        await makeWork(repo: repo, now: now, steps: 20, scheduler: scheduler).run(now: now)
        XCTAssertTrue(scheduler.posts.isEmpty, "no pre-alarm policy → no prompt")
    }

    func testUnreadableRepositoryPostsNothing() async throws {
        let now = try iso("2026-08-17T06:55:00Z")
        let scheduler = InMemoryPreAlarmNotificationScheduler()
        await makeWork(repo: FailingAlarmRepository(), now: now, steps: 20, scheduler: scheduler)
            .run(now: now)
        XCTAssertTrue(scheduler.posts.isEmpty, "fail-safe: an unreadable repo posts nothing (#9)")
    }
}

/// A repository whose reads fail — to exercise the work's fail-safe (an unreadable store posts
/// nothing, so a critical alarm is never affected by a failed pre-alarm pass, #9).
private struct FailingAlarmRepository: AlarmRepository {
    func save(_ alarm: Alarm) async throws { throw AlarmRepositoryError.storageUnavailable }
    func alarm(id: AlarmID) async throws -> Alarm? { throw AlarmRepositoryError.storageUnavailable }
    func allAlarms() async throws -> [Alarm] { throw AlarmRepositoryError.storageUnavailable }
    func deleteAlarm(id: AlarmID) async throws { throw AlarmRepositoryError.storageUnavailable }
}
