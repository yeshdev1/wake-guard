import Foundation

@testable import WakeGuard

/// A configurable in-memory `AlarmManagerAdapter` fake (WG-024). It tracks the
/// "system" scheduled alarms (schedule adds, cancel removes, snooze reschedules),
/// records calls for assertions, and lets tests set the authorization state, seed
/// the system state directly (to simulate divergence, WG-029), and **inject a
/// per-operation failure or uncertain outcome**. Thread-safe via `Synchronized`, so
/// it is `Sendable`.
///
/// An injected error is thrown *without* applying the change — so an injected
/// `.uncertain` models "the op may not have happened"; the complementary
/// "happened but unconfirmed" case is modeled by `setScheduled(_:)` after the call.
final class FakeAlarmManagerAdapter: AlarmManagerAdapter {

    /// Which adapter call an injected error applies to.
    enum Operation: Sendable, Hashable {
        case requestAuthorization
        case schedule
        case cancel
        case stopRing
        case snooze
        case query
    }

    struct SnoozeCall: Sendable, Equatable {
        let alarmID: AlarmID
        let until: Date
    }

    private struct State: Sendable {
        var authorization: AlarmAuthorizationState
        var scheduled: [AlarmID: ScheduledAlarmSnapshot] = [:]
        var injected: [Operation: AlarmManagerError] = [:]
        var scheduledRequests: [AlarmScheduleRequest] = []
        var cancelledAlarmIDs: [AlarmID] = []
        var stoppedRingIDs: [AlarmID] = []
        var snoozeCalls: [SnoozeCall] = []
        var requestAuthorizationCallCount = 0
    }

    private let state: Synchronized<State>

    init(authorization: AlarmAuthorizationState = .authorized) {
        state = Synchronized(State(authorization: authorization))
    }

    // MARK: - Test configuration

    func setAuthorization(_ value: AlarmAuthorizationState) {
        state.mutate { $0.authorization = value }
    }

    /// Make every subsequent call to `operation` throw `error` (sticky), or clear it
    /// with `nil`.
    func inject(_ error: AlarmManagerError?, on operation: Operation) {
        state.mutate { $0.injected[operation] = error }
    }

    /// Replace the system-scheduled set directly — used to simulate divergence (the
    /// system holds an alarm the app never scheduled, or is missing one it did).
    func setScheduled(_ snapshots: [ScheduledAlarmSnapshot]) {
        state.mutate { store in
            store.scheduled = [:]
            for snapshot in snapshots { store.scheduled[snapshot.alarmID] = snapshot }
        }
    }

    // MARK: - Inspection

    /// `scheduledRequests` / `cancelledAlarmIDs` / `snoozeCalls` are append-only *call
    /// logs* (one entry per invocation), distinct from `currentlyScheduled` (the
    /// idempotent system set): two schedules of one id log twice but leave one alarm.
    var scheduledRequests: [AlarmScheduleRequest] { state.get().scheduledRequests }
    var cancelledAlarmIDs: [AlarmID] { state.get().cancelledAlarmIDs }
    /// Append-only log of `stopRing` calls (one per invocation) — a duplicate stop that the outbox
    /// dedups reaches the adapter only once, so a second entry here would flag a lost idempotency.
    var stoppedRingIDs: [AlarmID] { state.get().stoppedRingIDs }
    var snoozeCalls: [SnoozeCall] { state.get().snoozeCalls }
    var requestAuthorizationCallCount: Int { state.get().requestAuthorizationCallCount }
    var currentlyScheduled: [ScheduledAlarmSnapshot] {
        Self.sorted(state.get().scheduled)
    }

    // MARK: - AlarmManagerAdapter

    func authorizationState() async -> AlarmAuthorizationState {
        state.get().authorization
    }

    func requestAuthorization() async throws -> AlarmAuthorizationState {
        let result: Result<AlarmAuthorizationState, AlarmManagerError> = state.mutate { store in
            store.requestAuthorizationCallCount += 1
            if let error = store.injected[.requestAuthorization] { return .failure(error) }
            return .success(store.authorization)
        }
        return try result.get()
    }

    func schedule(_ request: AlarmScheduleRequest) async throws {
        let injected: AlarmManagerError? = state.mutate { store in
            if let error = store.injected[.schedule] { return error }
            store.scheduledRequests.append(request)
            store.scheduled[request.alarmID] = ScheduledAlarmSnapshot(
                alarmID: request.alarmID, fireTime: request.fireTime,
                isCritical: request.isCritical)
            return nil
        }
        if let injected { throw injected }
    }

    func cancel(alarmID: AlarmID) async throws {
        let injected: AlarmManagerError? = state.mutate { store in
            if let error = store.injected[.cancel] { return error }
            store.cancelledAlarmIDs.append(alarmID)
            store.scheduled[alarmID] = nil
            return nil
        }
        if let injected { throw injected }
    }

    func stopRing(alarmID: AlarmID) async throws {
        let injected: AlarmManagerError? = state.mutate { store in
            if let error = store.injected[.stopRing] { return error }
            store.stoppedRingIDs.append(alarmID)
            return nil
        }
        if let injected { throw injected }
    }

    func snooze(alarmID: AlarmID, until: Date) async throws {
        let injected: AlarmManagerError? = state.mutate { store in
            if let error = store.injected[.snooze] { return error }
            store.snoozeCalls.append(SnoozeCall(alarmID: alarmID, until: until))
            // Snooze reschedules an existing alarm (keeping its criticality); snoozing
            // an alarm the system does not hold is a no-op, not a fabricated entry.
            if let existing = store.scheduled[alarmID] {
                store.scheduled[alarmID] = ScheduledAlarmSnapshot(
                    alarmID: alarmID, fireTime: until, isCritical: existing.isCritical)
            }
            return nil
        }
        if let injected { throw injected }
    }

    func scheduledAlarms() async throws -> [ScheduledAlarmSnapshot] {
        let result: Result<[ScheduledAlarmSnapshot], AlarmManagerError> = state.mutate { store in
            if let error = store.injected[.query] { return .failure(error) }
            return .success(Self.sorted(store.scheduled))
        }
        return try result.get()
    }

    /// Deterministic ordering: by fire time, then alarm id.
    private static func sorted(_ scheduled: [AlarmID: ScheduledAlarmSnapshot])
        -> [ScheduledAlarmSnapshot]
    {
        scheduled.values.sorted {
            ($0.fireTime, $0.alarmID.rawValue.uuidString)
                < ($1.fireTime, $1.alarmID.rawValue.uuidString)
        }
    }
}
