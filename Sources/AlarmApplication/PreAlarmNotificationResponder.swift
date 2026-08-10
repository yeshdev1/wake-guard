import Foundation

/// The pre-alarm prompt notification's `userInfo` payload (WG-08x composition): the minimal context a
/// tapped action needs to route (WG-083 → `PreAlarmResponseRouter`). Encoded as primitive strings so it
/// survives a UserNotifications round-trip, and decoded **fail-closed** — any missing / malformed /
/// non-finite / negative field yields `nil`, so a corrupt notification is ignored (the alarm is
/// unchanged, #7), never mis-routed to the wrong alarm or occurrence.
enum PreAlarmNotificationPayload {
    private enum Key {
        static let alarmID = "wg.prealarm.alarmID"
        static let occurrence = "wg.prealarm.occurrence"
        static let criticality = "wg.prealarm.criticality"
        static let remindersUsed = "wg.prealarm.remindersUsed"
    }

    static func encode(_ context: PreAlarmResponseContext) -> [AnyHashable: Any] {
        [
            Key.alarmID: context.alarmID.rawValue.uuidString,
            Key.occurrence: String(context.occurrence.timeIntervalSince1970),
            Key.criticality: context.criticality.rawValue,
            Key.remindersUsed: String(context.remindersUsed),
        ]
    }

    static func decode(_ userInfo: [AnyHashable: Any]) -> PreAlarmResponseContext? {
        guard let idString = userInfo[Key.alarmID] as? String,
            let uuid = UUID(uuidString: idString),
            let occurrenceString = userInfo[Key.occurrence] as? String,
            let seconds = Double(occurrenceString), seconds.isFinite,
            let criticalityString = userInfo[Key.criticality] as? String,
            let criticality = Criticality(rawValue: criticalityString),
            let usedString = userInfo[Key.remindersUsed] as? String, let used = Int(usedString),
            used >= 0
        else { return nil }
        return PreAlarmResponseContext(
            alarmID: AlarmID(uuid), occurrence: Date(timeIntervalSince1970: seconds),
            criticality: criticality, remindersUsed: used)
    }
}

/// The pre-alarm prompt notification surface behind a port (CLAUDE.md: UserNotifications is wrapped) so
/// the runtime is testable and only one adapter touches the framework. Posting / re-posting / cancelling
/// a prompt never touches the alarm — the prompt is the advisory surface only (#7/#8).
protocol PreAlarmNotificationScheduling: Sendable {
    /// Request notification authorization (alert + sound) so prompts can be delivered — idempotent, and
    /// a denial simply means no prompt appears (the alarm still rings; advisory-only, #7/#8).
    func requestAuthorization() async
    /// Register the prompt category + its actions (idempotent; safe to call every launch).
    func registerPromptCategory() async
    /// Post (or re-post, for remind-later) the prompt for this occurrence, firing at `date`.
    func postPrompt(_ context: PreAlarmResponseContext, at date: Date) async
    /// Remove any pending prompt for this occurrence (e.g. once the user has handled it).
    func cancelPrompt(alarmID: AlarmID, occurrence: Date) async
}

/// What the app shell should do after a tapped pre-alarm action is routed + executed. The safety-
/// critical `.submit` has already gone through `AlarmCommandProcessor`; the rest are advisory.
enum PreAlarmResponseEffect: Sendable, Equatable {
    /// The command was submitted through the processor. If `outcome` is `.needsConfirmation`, the app
    /// must foreground to collect explicit confirmation and re-submit `userConfirmed: true` (#6); the
    /// alarm is unchanged until then.
    case submitted(outcome: CommandOutcome, command: AlarmCommand)
    /// Remind-later re-armed the prompt at this instant (WG-087) — the alarm is untouched.
    case rescheduled(at: Date)
    /// Remind-later is exhausted — no re-prompt; the alarm rings as scheduled.
    case remindingStopped(ReminderExhaustion)
    /// Foreground the app to the change-time picker (WG-086); nothing changed yet.
    case presentChangeTimeUI(AlarmID)
    /// Nothing to do — keep acknowledged, an unknown action, or a corrupt payload (#7).
    case none
}

/// Executes a tapped pre-alarm notification action (WG-08x composition): decode the payload → route
/// (`PreAlarmResponseRouter`) → act. The one authority it exercises is submitting the routed command
/// through `AlarmCommandProcessor` (source `.notificationAction`, `userConfirmed: false` — so a
/// critical/imminent change comes back `.needsConfirmation`, #6); a remind-later re-posts the advisory
/// prompt (never the alarm, #7/#8), and anything else changes nothing. A corrupt payload is ignored —
/// never mis-applied to the wrong alarm/occurrence.
struct PreAlarmNotificationResponder: Sendable {
    let processor: any AlarmCommandProcessing
    let notifications: any PreAlarmNotificationScheduling
    var reminderConfig: PreAlarmReminder.Config = .default

    func handle(actionIdentifier: String, userInfo: [AnyHashable: Any], now: Date) async
        -> PreAlarmResponseEffect
    {
        guard let context = PreAlarmNotificationPayload.decode(userInfo) else { return .none }
        switch PreAlarmResponseRouter.route(
            actionIdentifier: actionIdentifier, context: context, now: now,
            reminderConfig: reminderConfig)
        {
        case .submit(let command):
            let outcome = await processor.process(
                command, from: .notificationAction, by: .user, userConfirmed: false)
            // A turn-off that took effect (applied, or deferred-but-persisted) reaps any pending
            // re-prompt for this occurrence — so a remind-later scheduled earlier never re-prompts
            // about an alarm already turned off. `keepOriginal`, and a needs-confirmation critical
            // turn-off (unchanged, #6), leave any prompt in place.
            switch (command, outcome) {
            case (.cancelOccurrence, .applied), (.cancelOccurrence, .uncertain):
                await notifications.cancelPrompt(
                    alarmID: context.alarmID, occurrence: context.occurrence)
            default:
                break
            }
            return .submitted(outcome: outcome, command: command)
        case .reschedulePrompt(let date):
            let next = PreAlarmResponseContext(
                alarmID: context.alarmID, occurrence: context.occurrence,
                criticality: context.criticality, remindersUsed: context.remindersUsed + 1)
            await notifications.postPrompt(next, at: date)
            return .rescheduled(at: date)
        case .stopReminding(let reason):
            return .remindingStopped(reason)
        case .presentChangeTimeUI:
            return .presentChangeTimeUI(context.alarmID)
        case .ignored:
            return .none
        }
    }
}
