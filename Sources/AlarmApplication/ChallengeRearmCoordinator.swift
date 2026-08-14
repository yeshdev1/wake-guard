import Foundation

/// Persists the set of **unsatisfied** critical wake challenges (WG-284) so a re-arm decision survives the
/// app being suspended between the ring and the next foreground. A port — the production impl is Core Data
/// backed; tests use an in-memory fake.
protocol PendingChallengeStore: Sendable {
    /// Record or replace the pending challenge for its alarm (used to start tracking and to bump attempts).
    func upsert(_ pending: PendingChallenge) async
    /// The pending challenge for `alarmID`, or `nil` if the ring has been satisfied / never tracked.
    func pending(for alarmID: AlarmID) async -> PendingChallenge?
    /// Stop tracking `alarmID` — called on a pass or once the re-arm cap is reached.
    func clear(_ alarmID: AlarmID) async
}

/// Issues an actual re-arm: reschedule the critical alarm to re-fire at `fireTime`. The production impl
/// routes through the command processor + adapter (policy-authorised, audited; only the adapter touches
/// `AlarmManager`, #1/#2). A port so the coordinator's decision logic is testable without AlarmKit.
protocol ChallengeReArming: Sendable {
    func rearm(alarmID: AlarmID, at fireTime: Date) async
}

/// Orchestrates the enforced walk challenge's re-arm loop (WG-284) — the CI-testable decision layer that
/// ties WG-073 (challenge → authorised stop) to `RearmPolicy` (WG-283, the bounded cap). It holds **no**
/// alarm authority itself: it only records/clears pending challenges and asks the injected re-arming port to
/// reschedule. Critical-only (decision 2); a pass clears tracking so it never re-arms; a confirmed
/// stop-without-pass re-arms within the cap, then stops so the alarm always ends (#-safety, WG-285).
///
/// Detecting *that* a ring was stopped without a pass is device-fed (AlarmKit alerting observation on
/// foreground, WG-286) — this type is called with that determination, keeping it deterministic.
struct ChallengeRearmCoordinator: Sendable {
    let store: any PendingChallengeStore
    let rearming: any ChallengeReArming
    let clock: any WallClock
    var config: RearmConfiguration = .default

    /// A critical challenge alarm fired — start tracking it as unsatisfied. Standard alarms are ignored
    /// (decision 2): only a critical alarm ever re-arms.
    func trackFiredChallenge(alarmID: AlarmID, fireTime: Date, isCritical: Bool) async {
        guard isCritical else { return }
        await store.upsert(PendingChallenge(alarmID: alarmID, originalFireTime: fireTime))
    }

    /// The challenge passed (WG-073 stop) — clear tracking so this wake never re-arms.
    func challengePassed(alarmID: AlarmID) async {
        await store.clear(alarmID)
    }

    /// A tracked critical alarm was stopped **without** a pass. Re-arm within the cap; otherwise stop and
    /// clear so the alarm ends (WG-285). A no-op if nothing is tracked (already passed / never critical).
    func stoppedWithoutPass(alarmID: AlarmID) async {
        guard var pending = await store.pending(for: alarmID) else { return }
        switch RearmPolicy.next(after: clock.now, pending: pending, config: config) {
        case .rearm(let fireTime):
            pending.attempts += 1
            await store.upsert(pending)
            await rearming.rearm(alarmID: alarmID, at: fireTime)
        case .stop:
            await store.clear(alarmID)
        }
    }
}
