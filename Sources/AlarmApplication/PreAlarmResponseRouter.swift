import Foundation

/// The context a tapped pre-alarm notification carries (WG-08x composition) — read from the
/// notification's `userInfo`. `remindersUsed` is the running count the runtime persists per prompt
/// session (WG-087).
struct PreAlarmResponseContext: Sendable, Equatable {
    let alarmID: AlarmID
    let occurrence: Date
    let criticality: Criticality
    let remindersUsed: Int
}

/// What the runtime should do in response to a pre-alarm prompt action (WG-08x composition). It maps
/// a tapped action to a **decision**; the runtime executes it. It carries no authority itself — a
/// `.submit` is handed to `AlarmCommandProcessor` (which authorizes it, gating a critical/imminent
/// change on confirmation, #6), a `.reschedulePrompt` re-arms the prompt notification (never the
/// alarm), and the rest change nothing (#7/#8).
enum PreAlarmResponse: Sendable, Equatable {
    /// Submit this command through `AlarmCommandProcessor`. `userConfirmed` is `false` here — the
    /// processor returns `.needsConfirmation` for a critical / imminent change, and the runtime then
    /// foregrounds to collect explicit confirmation and re-submits with `userConfirmed: true` (#6).
    case submit(AlarmCommand)
    /// Re-show the prompt at this instant (remind-later, WG-087) — the alarm is untouched.
    case reschedulePrompt(at: Date)
    /// Remind-later is exhausted (capped / no safe window) — no re-prompt; the alarm rings as
    /// scheduled.
    case stopReminding(ReminderExhaustion)
    /// Change-time needs the in-app picker (WG-086) — foreground the app; nothing changes yet.
    case presentChangeTimeUI
    /// Unknown / unhandled action — ignore; the alarm is unchanged (#7).
    case ignored
}

/// Routes a tapped pre-alarm prompt action (WG-083 identifiers) to a `PreAlarmResponse` — the
/// composition glue discharging the WG-084 (keep), WG-085 (turn-off-today), and WG-087 (remind-later)
/// response handoffs. Pure and deterministic (`now` injected); it decides, the runtime acts.
enum PreAlarmResponseRouter {

    static func route(
        actionIdentifier: String, context: PreAlarmResponseContext, now: Date,
        reminderConfig: PreAlarmReminder.Config = .default
    ) -> PreAlarmResponse {
        switch actionIdentifier {
        case PreAlarmPromptAction.keep.identifier:
            // Keep is the #7 no-op acknowledgement (WG-084).
            return .submit(.keepOriginal(context.alarmID))
        case PreAlarmPromptAction.turnOffToday.identifier:
            // Occurrence-level cancel (WG-085); the processor gates a critical/imminent turn-off on
            // confirmation, so the runtime foregrounds on `.needsConfirmation`.
            return .submit(.cancelOccurrence(context.alarmID, fireTime: context.occurrence))
        case PreAlarmPromptAction.remindLater.identifier:
            switch PreAlarmReminder.next(
                now: now, alarmFireTime: context.occurrence, remindersUsed: context.remindersUsed,
                criticality: context.criticality, config: reminderConfig)
            {
            case .remind(let at, _): return .reschedulePrompt(at: at)
            case .exhausted(let reason): return .stopReminding(reason)
            }
        case PreAlarmPromptAction.changeTime.identifier:
            return .presentChangeTimeUI
        default:
            return .ignored
        }
    }
}
