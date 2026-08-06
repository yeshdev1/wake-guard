import Foundation

/// A concrete instruction to change alarm state. Distinct from `AlarmProposal`:
/// an `AlarmCommand` is what the command processor (WG-027) applies *after* the
/// policy engine (WG-028) authorizes it. AI never produces an `AlarmCommand`
/// directly (SAFETY_INVARIANTS #4) — it produces an `AlarmProposal`, which only
/// the policy engine may turn into a command.
///
/// `Codable` so a pending command can be persisted in the outbox (WG-016). An
/// occurrence is identified by its alarm and scheduled `fireTime` (absolute
/// instant); the occurrence calculation itself is WG-020.
enum AlarmCommand: Codable, Sendable, Equatable, Hashable {
    case create(Alarm)
    case update(Alarm)
    case enable(AlarmID)
    case disable(AlarmID)
    /// Permanently remove the alarm (a hard delete): drop local state and cancel the system
    /// alarm. Distinct from `disable`, which keeps the alarm but turns it off.
    case delete(AlarmID)
    case cancelOccurrence(AlarmID, fireTime: Date)
    case rescheduleOccurrence(AlarmID, fireTime: Date, to: Date)
    case snooze(AlarmID)
    case markChallengePassed(AlarmID)
    case reconcile(AlarmID)
    case recover(AlarmID)

    /// The alarm this command targets.
    var alarmID: AlarmID {
        switch self {
        case .create(let alarm), .update(let alarm):
            alarm.id
        case .enable(let id), .disable(let id), .delete(let id), .snooze(let id),
            .markChallengePassed(let id), .reconcile(let id), .recover(let id):
            id
        case .cancelOccurrence(let id, _), .rescheduleOccurrence(let id, _, _):
            id
        }
    }
}
