import Foundation

/// The alarm-mutation boundary the UI depends on (WG-042). Every user- or agent-initiated
/// alarm change is submitted here and applied by `AlarmCommandProcessor` — the **sole**
/// conformer and the single command-serialization boundary (#2) — authorized by the policy
/// engine (#3), audited (#46), and synced to AlarmKit. Screens depend on this protocol, not
/// the concrete actor, so a fake can stand in for tests and no screen can reach the adapter
/// or persistence directly.
protocol AlarmCommandProcessing: Sendable {
    func process(
        _ command: AlarmCommand, from source: CommandSource, by actor: AuditActor,
        userConfirmed: Bool
    ) async -> CommandOutcome

    /// Reconcile the system alarm authority against the persisted desired state (WG-029) — run at
    /// launch and on every foreground. Idempotent and fails safe (#10): an unreadable ground-truth or
    /// desired state repairs nothing, never drops an alarm. Opportunistic — never required for a
    /// critical alarm to ring (#9).
    func reconcile() async -> ReconciliationSummary
}

extension AlarmCommandProcessor: AlarmCommandProcessing {}
