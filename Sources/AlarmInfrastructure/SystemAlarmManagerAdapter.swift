import AlarmKit
import Foundation
import SwiftUI

/// AlarmKit metadata for WakeGuard alarms. Empty today — WakeGuard carries no extra
/// per-alarm metadata in the system alarm; the domain owns alarm state.
struct WakeGuardAlarmMetadata: AlarmMetadata {}

/// The real AlarmKit-backed `AlarmManagerAdapter` (WG-026, minimal). Per
/// SAFETY_INVARIANTS #1 this is the **only** component that calls `AlarmManager`.
/// Schedules a per-occurrence **`.fixed`** alarm at the caller-resolved fire instant
/// (the pure engine owns recurrence/tz/DST/travel — see `AlarmKitScheduleMapper`);
/// correlation is by identity (`AlarmID.rawValue` == `AlarmKit.Alarm.ID`).
///
/// Every scheduled alarm is a *system* alarm that rings through silent mode and Focus
/// by default (the #6–#8 baseline — AlarmKit exposes no app-facing criticality knob,
/// so there is nothing to escalate here). The domain's `.critical` *tier* — its
/// distinct guarantees, e.g. explicit cancel-confirmation — is enforced by the policy
/// / command layer (WG-028/WG-027), not the adapter; and criticality cannot be read
/// back from AlarmKit (WG-029 compares against locally-tracked intent). The ring-
/// through-silent/Focus/DND assumption **must be verified on a device** (WG-030).
///
/// Minimal: the alert is a plain title + Stop button (real UX / localization / snooze
/// action is a later task). Not unit-tested — `AlarmManager.shared` needs a device
/// (see DECISIONS WG-026 and the WG-030 real-device checklist).
struct SystemAlarmManagerAdapter: AlarmManagerAdapter {

    func authorizationState() async -> AlarmAuthorizationState {
        Self.map(AlarmManager.shared.authorizationState)
    }

    func requestAuthorization() async throws -> AlarmAuthorizationState {
        do {
            return Self.map(try await AlarmManager.shared.requestAuthorization())
        } catch {
            throw Self.map(error)
        }
    }

    func schedule(_ request: AlarmScheduleRequest) async throws {
        try await scheduleFixed(
            id: request.alarmID.rawValue, at: request.fireTime,
            title: LocalizedStringResource(stringLiteral: request.title))
    }

    func cancel(alarmID: AlarmID) async throws {
        // Cancelling an id the system does not hold is a no-op, not an error (port
        // contract) — check presence first so an unknown id never surfaces as a
        // spurious failure to a reconciler. If the query itself fails, fall through to
        // a best-effort cancel.
        if let alarms = try? AlarmManager.shared.alarms,
            !alarms.contains(where: { $0.id == alarmID.rawValue })
        {
            return
        }
        do {
            try AlarmManager.shared.cancel(id: alarmID.rawValue)
        } catch {
            throw Self.map(error)
        }
    }

    func snooze(alarmID: AlarmID, until: Date) async throws {
        // Reschedule the same id to fire at `until` (schedule replaces on id). The
        // original title is not available here, so a generic label is used — minimal.
        try await scheduleFixed(id: alarmID.rawValue, at: until, title: "Alarm")
    }

    func scheduledAlarms() async throws -> [ScheduledAlarmSnapshot] {
        let alarms: [AlarmKit.Alarm]
        do {
            alarms = try AlarmManager.shared.alarms
        } catch {
            throw Self.map(error)
        }
        // Only `.fixed` alarms have a scalar fire instant (all WakeGuard alarms are
        // `.fixed`). AlarmKit does not expose criticality on read-back, so `isCritical`
        // cannot be verified here — WG-029 must compare against locally-tracked intent.
        return alarms.compactMap { alarm in
            guard case .fixed(let fireTime)? = alarm.schedule else { return nil }
            return ScheduledAlarmSnapshot(
                alarmID: AlarmID(alarm.id), fireTime: fireTime, isCritical: false)
        }
    }

    private func scheduleFixed(id: UUID, at fireTime: Date, title: LocalizedStringResource)
        async throws
    {
        // A denial must not be misread as a scheduling failure — surface it as
        // `.notAuthorized` so the caller preserves the last safe alarm (#10).
        guard AlarmManager.shared.authorizationState == .authorized else {
            throw AlarmManagerError.notAuthorized
        }
        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: AlarmButton(
                text: "Stop", textColor: .white, systemImageName: "stop.circle.fill"))
        let attributes = AlarmAttributes<WakeGuardAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeGuardAlarmMetadata(), tintColor: .accentColor)
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(fireTime), attributes: attributes)
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ state: AlarmManager.AuthorizationState) -> AlarmAuthorizationState {
        switch state {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .denied  // fail closed — never assume authorized
        }
    }

    /// Maps an AlarmKit error to a typed, **coarse** `AlarmManagerError` — never raw
    /// error text, which could embed a title or other context (#41). Internal so the
    /// redaction guarantee is unit-tested without a device.
    static func map(_ error: Error) -> AlarmManagerError {
        if error is CancellationError {
            // The operation may already have applied; the caller must reconcile (#10).
            return .uncertain
        }
        if let alarmError = error as? AlarmManager.AlarmError {
            switch alarmError {
            case .maximumLimitReached:
                return .failed(reason: "The system alarm limit was reached.")
            @unknown default:
                return .failed(reason: "The alarm could not be scheduled.")
            }
        }
        return .failed(reason: "The alarm could not be scheduled.")
    }
}
