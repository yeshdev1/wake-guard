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
}

extension AlarmCommandProcessor: AlarmCommandProcessing {}
