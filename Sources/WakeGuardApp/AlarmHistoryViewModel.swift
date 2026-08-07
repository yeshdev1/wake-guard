import Foundation
import Observation

/// One audit event presented safely for the history UI (WG-048). It carries only user-safe
/// fields — who acted, what changed (the event's `userVisibleReason`), when, from where, the
/// outcome, and whether it was a recovery/system action (#50). It deliberately omits the state
/// hashes and the correlation id (internal fingerprints, #41), so those can't leak to the UI.
struct AlarmHistoryItem: Identifiable, Equatable, Sendable {
    let id: AuditEventID
    let who: String
    /// The event's `userVisibleReason` — already a coarse, user-safe string by construction (#41).
    let what: String
    /// Relative time for the row (e.g. "2 hours ago").
    let when: String
    /// Absolute time for the detail (e.g. "Nov 14, 2023, 7:00 AM").
    let whenDetailed: String
    let fromSource: String
    let outcome: Outcome
    /// Whether this was a system-originated action (reconciliation / recovery / migration) rather
    /// than a change the user made — drives a distinct icon + "System" tag and a VoiceOver prefix
    /// so recovery/reconciliation entries are distinguishable from ordinary edits (#50).
    let isSystem: Bool
    let accessibilityLabel: String
}

enum AlarmHistoryState: Equatable, Sendable {
    case loading
    case empty
    case loaded([AlarmHistoryItem])
    case failed(reason: String)
}

/// Read-only history for one alarm (WG-048): loads its append-only audit trail and maps each
/// event to a user-safe row. It only *reads* the audit repository — it never mutates anything
/// (#2), and it maps away every internal fingerprint before the value reaches the view (#41).
@MainActor
@Observable
final class AlarmHistoryViewModel {
    private(set) var state: AlarmHistoryState = .loading

    private let audit: any AuditRepository
    private let clock: any WallClock
    private let alarmID: AlarmID

    init(audit: any AuditRepository, clock: any WallClock, alarmID: AlarmID) {
        self.audit = audit
        self.clock = clock
        self.alarmID = alarmID
    }

    func load() async {
        do {
            let events = try await audit.events(forAlarm: alarmID)
            let items =
                events
                .sorted { $0.timestamp > $1.timestamp }  // newest first
                .map { Self.item(from: $0, now: clock.now) }
            state = items.isEmpty ? .empty : .loaded(items)
        } catch {
            state = .failed(reason: "We couldn’t load this alarm’s history right now.")
        }
    }

    /// Map a raw audit event to a safe row. Only `userVisibleReason` (a coarse #41-safe string)
    /// and the non-sensitive metadata cross over; the state hashes and correlation id never do.
    nonisolated static func item(from event: AuditEvent, now: Date) -> AlarmHistoryItem {
        let who = actorLabel(event.actor)
        let when = relative(event.timestamp, now: now)
        let system = isSystemOriginated(event)
        let label =
            (system ? "System action. " : "")
            + "\(who): \(event.userVisibleReason) \(outcomeLabel(event.outcome)), \(when)."
        return AlarmHistoryItem(
            id: event.id, who: who, what: event.userVisibleReason, when: when,
            whenDetailed: event.timestamp.formatted(date: .abbreviated, time: .shortened),
            fromSource: sourceLabel(event.source), outcome: event.outcome, isSystem: system,
            accessibilityLabel: label)
    }

    /// A system-originated action (reconciliation / recovery / migration) — not a change the user
    /// directly made. Distinguished from ordinary edits and approved suggestions (#50).
    nonisolated static func isSystemOriginated(_ event: AuditEvent) -> Bool {
        switch event.actor {
        case .systemReconciliation, .recovery, .migration:
            return true
        case .user, .approvedAgentProposal:
            return event.source == .reconciliation || event.source == .recovery
                || event.source == .migration
        }
    }

    nonisolated static func actorLabel(_ actor: AuditActor) -> String {
        switch actor {
        case .user: "You"
        case .systemReconciliation: "System check"
        case .approvedAgentProposal: "Approved suggestion"
        case .migration: "App update"
        case .recovery: "Automatic recovery"
        }
    }

    nonisolated static func sourceLabel(_ source: CommandSource) -> String {
        switch source {
        case .userInterface: "In the app"
        case .notificationAction: "From a notification"
        case .agentProposal: "A suggestion"
        case .reconciliation: "A system check"
        case .migration: "An app update"
        case .recovery: "Recovery"
        }
    }

    nonisolated static func outcomeLabel(_ outcome: Outcome) -> String {
        switch outcome {
        case .succeeded: "Applied"
        case .failed: "Failed"
        case .rejected: "Not allowed"
        case .noOp: "No change needed"
        }
    }

    nonisolated private static func relative(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
