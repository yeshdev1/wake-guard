import Foundation
import XCTest

@testable import WakeGuard

/// WG-284: the re-arm coordinator tying WG-073 (challenge → stop) to `RearmPolicy` (WG-283, the cap).
/// Pins critical-only tracking, that a pass clears tracking (never re-arms), that a stop-without-pass
/// re-arms at the interval and bumps attempts, that it stops at the cap so the alarm always ends, and that
/// an untracked alarm is a no-op.
final class ChallengeRearmCoordinatorTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 284)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private actor FakeStore: PendingChallengeStore {
        private var byID: [AlarmID: PendingChallenge] = [:]
        func upsert(_ pending: PendingChallenge) { byID[pending.alarmID] = pending }
        func pending(for alarmID: AlarmID) -> PendingChallenge? { byID[alarmID] }
        func clear(_ alarmID: AlarmID) { byID[alarmID] = nil }
    }

    private actor RecordingReArming: ChallengeReArming {
        private(set) var calls: [(id: AlarmID, at: Date)] = []
        func rearm(alarmID: AlarmID, at fireTime: Date) { calls.append((alarmID, fireTime)) }
        func count() -> Int { calls.count }
        func lastFireTime() -> Date? { calls.last?.at }
    }

    private func makeCoordinator(
        store: FakeStore, rearming: RecordingReArming, config: RearmConfiguration = .default
    ) -> ChallengeRearmCoordinator {
        ChallengeRearmCoordinator(
            store: store, rearming: rearming, clock: TestClock(now: now), config: config)
    }

    func testOnlyCriticalAlarmsAreTracked() async {
        let store = FakeStore()
        let coordinator = makeCoordinator(store: store, rearming: RecordingReArming())
        let standard = AlarmID(ids.next())
        let critical = AlarmID(ids.next())
        await coordinator.trackFiredChallenge(alarmID: standard, fireTime: now, isCritical: false)
        await coordinator.trackFiredChallenge(alarmID: critical, fireTime: now, isCritical: true)
        let standardPending = await store.pending(for: standard)
        let criticalPending = await store.pending(for: critical)
        XCTAssertNil(standardPending, "a standard alarm never re-arms")
        XCTAssertNotNil(criticalPending, "a critical alarm is tracked")
    }

    func testAPassClearsTrackingSoItNeverReArms() async {
        let store = FakeStore()
        let rearming = RecordingReArming()
        let coordinator = makeCoordinator(store: store, rearming: rearming)
        let id = AlarmID(ids.next())
        await coordinator.trackFiredChallenge(alarmID: id, fireTime: now, isCritical: true)
        await coordinator.challengePassed(alarmID: id)
        // A stop-without-pass arriving after the pass must be a no-op.
        await coordinator.stoppedWithoutPass(alarmID: id)
        let calls = await rearming.count()
        let pending = await store.pending(for: id)
        XCTAssertEqual(calls, 0, "a passed challenge never re-arms")
        XCTAssertNil(pending)
    }

    func testStopWithoutPassReArmsAtTheIntervalAndBumpsAttempts() async {
        let store = FakeStore()
        let rearming = RecordingReArming()
        let coordinator = makeCoordinator(store: store, rearming: rearming)
        let id = AlarmID(ids.next())
        await coordinator.trackFiredChallenge(alarmID: id, fireTime: now, isCritical: true)
        await coordinator.stoppedWithoutPass(alarmID: id)
        let calls = await rearming.count()
        let fireTime = await rearming.lastFireTime()
        let pending = await store.pending(for: id)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fireTime, now.addingTimeInterval(120), "re-arms 2 minutes out")
        XCTAssertEqual(pending?.attempts, 1, "the attempt count is bumped")
    }

    func testStopsAtTheCapSoTheAlarmAlwaysEnds() async {
        let store = FakeStore()
        let rearming = RecordingReArming()
        let config = RearmConfiguration(interval: 120, maxAttempts: 2)
        let coordinator = makeCoordinator(store: store, rearming: rearming, config: config)
        let id = AlarmID(ids.next())
        await coordinator.trackFiredChallenge(alarmID: id, fireTime: now, isCritical: true)
        await coordinator.stoppedWithoutPass(alarmID: id)  // attempts 0 -> re-arm -> 1
        await coordinator.stoppedWithoutPass(alarmID: id)  // attempts 1 -> re-arm -> 2
        await coordinator.stoppedWithoutPass(alarmID: id)  // attempts 2 == cap -> stop
        let calls = await rearming.count()
        let pending = await store.pending(for: id)
        XCTAssertEqual(calls, 2, "re-armed up to the cap, then stopped")
        XCTAssertNil(pending, "at the cap the pending is cleared — the alarm ends")
    }

    func testUntrackedAlarmIsANoOp() async {
        let rearming = RecordingReArming()
        let coordinator = makeCoordinator(store: FakeStore(), rearming: rearming)
        await coordinator.stoppedWithoutPass(alarmID: AlarmID(ids.next()))
        let calls = await rearming.count()
        XCTAssertEqual(calls, 0)
    }
}
