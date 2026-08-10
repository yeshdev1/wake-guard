import Foundation

/// How much autonomy the user grants the advisory agent (WG-171). The MVP offers only the two
/// conservative modes; `autoAdjust` exists in the type for forward-compatibility but is **not selectable**
/// (ADR: auto-adjust is disabled for the MVP) and, even if set, never silently applies a change.
enum AgentPermissionMode: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// The agent only *recommends*; the user applies any change manually.
    case recommendOnly
    /// The agent may *propose* a change but must ask for explicit confirmation before it is applied.
    case askBeforeActing
    /// Reserved for a future, tightly-bounded auto-application. **Not available in the MVP.**
    case autoAdjust

    /// The modes a user may select in the MVP — `autoAdjust` is deliberately excluded (ADR).
    static let selectable: [AgentPermissionMode] = [.recommendOnly, .askBeforeActing]

    var isSelectable: Bool { Self.selectable.contains(self) }
}

/// What the agent is permitted to do with a proposed change (WG-171). There is **no auto-apply action** —
/// the agent can only surface a recommendation or ask for confirmation, so it can never mutate an alarm
/// without the user in the loop.
enum AgentAction: Sendable, Equatable, Hashable {
    /// Surface the suggestion; never apply it. The user applies manually (which itself is policy-gated).
    case recommendOnly
    /// Ask the user; apply only on explicit confirmation.
    case requestConfirmation
}

/// The deterministic policy mapping a permission mode + target to what the agent may do (WG-171). Its
/// central guarantee: a **critical** alarm is never changed without explicit confirmation, in **any** mode
/// (#6), and there is no path that applies a change silently — auto-adjust is bounded to confirmation.
struct AgentActionPolicy: Sendable {
    func action(mode: AgentPermissionMode, targetIsCritical: Bool) -> AgentAction {
        // A critical alarm is immutable without confirmation, regardless of mode: recommend-only still
        // just recommends (the manual apply is itself policy-gated), every other mode must ask.
        if targetIsCritical {
            return mode == .recommendOnly ? .recommendOnly : .requestConfirmation
        }
        switch mode {
        case .recommendOnly:
            return .recommendOnly
        case .askBeforeActing:
            return .requestConfirmation
        case .autoAdjust:
            // MVP: auto-adjust is bounded to confirmation — it is never a silent apply (ADR).
            return .requestConfirmation
        }
    }
}
