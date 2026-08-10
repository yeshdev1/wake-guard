import Foundation

/// The result of handing an accepted agent proposal to the alarm boundary (WG-172).
enum AgentHandoffResult: Sendable, Equatable {
    /// The permission mode is recommend-only — the agent may only suggest; nothing was applied.
    case recommendedOnly
    /// An acting mode, but the user has not confirmed this change yet — the caller must confirm first.
    case needsUserConfirmation
    /// The change was submitted to the command boundary; carries the boundary's outcome.
    case handed(CommandOutcome)
}

/// Coordinates an **accepted** agent proposal into an alarm change (WG-172). It is deliberately powerless:
/// it depends only on the `AlarmCommandProcessing` boundary and the `AgentActionPolicy` — it **cannot touch
/// AlarmKit, persistence, or the policy engine directly** (#1/#2/#3). Every change it submits is attributed
/// to the AI (`CommandSource.agentProposal` / `AuditActor.approvedAgentProposal`), so the audit trail
/// always distinguishes an AI proposal from a direct user action (#46), and every submission passes through
/// the command boundary's policy authorization. It honours the permission mode (WG-171): recommend-only
/// never applies, and an acting mode applies only once the user has confirmed the change.
///
/// **Critical alarms:** the orchestrator's `targetIsCritical` gate is advisory UX (whether to prompt). The
/// *authoritative* guarantee is the policy engine itself — it re-reads the alarm's real criticality and
/// **rejects any destructive agent-proposed change to a critical alarm regardless of confirmation** (#4/#6).
/// So even a confirmed agent proposal can never weaken a critical alarm; the AI cannot suppress one at all.
struct AgentOrchestrator: Sendable {
    private let processor: any AlarmCommandProcessing
    private let permissionPolicy: AgentActionPolicy

    init(
        processor: any AlarmCommandProcessing,
        permissionPolicy: AgentActionPolicy = AgentActionPolicy()
    ) {
        self.processor = processor
        self.permissionPolicy = permissionPolicy
    }

    /// Apply an accepted proposal. `command` was built from a schema-validated, deterministically-checked
    /// intent (WG-163/165/168); `mode` is the user's permission setting; `targetIsCritical` is an
    /// **advisory** hint for whether to prompt (the engine independently re-checks real criticality and is
    /// the authority — see the type doc); `userConfirmed` is whether the user explicitly confirmed **this**
    /// change.
    func apply(
        _ command: AlarmCommand, mode: AgentPermissionMode, targetIsCritical: Bool,
        userConfirmed: Bool
    ) async -> AgentHandoffResult {
        switch permissionPolicy.action(mode: mode, targetIsCritical: targetIsCritical) {
        case .recommendOnly:
            return .recommendedOnly
        case .requestConfirmation:
            guard userConfirmed else { return .needsUserConfirmation }
            let outcome = await processor.process(
                command, from: .agentProposal, by: .approvedAgentProposal, userConfirmed: true)
            return .handed(outcome)
        }
    }
}
