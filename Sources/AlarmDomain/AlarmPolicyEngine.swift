import Foundation

/// Authorizes an `AlarmCommand` before the command processor applies it
/// (SAFETY_INVARIANTS #3 — every command must be authorized by the policy engine;
/// #31 — the policy engine, not the model, assigns criticality and authorization).
/// A domain-owned port: the command processor (WG-027) depends on it, and the real
/// deterministic engine — deciding on criticality, source, user confirmation, time
/// remaining, permissions, and feature settings (ARCHITECTURE §8) — is WG-028. Tests
/// use `FakeAlarmPolicyEngine`.
protocol AlarmPolicyEngine: Sendable {
    /// Whether `command`, issued from `source`, may be applied. `userConfirmed` is
    /// whether the user explicitly confirmed a destructive action — required to cancel,
    /// delay, or weaken a critical (or imminent) alarm (#6). The engine, not the
    /// caller, decides when confirmation is required.
    func authorize(
        _ command: AlarmCommand, from source: CommandSource, userConfirmed: Bool
    ) async -> PolicyDecision
}

/// The policy engine's verdict on a command.
enum PolicyDecision: Sendable, Equatable {
    case authorized
    /// Rejected — `reason` is a coarse, user-safe string (never raw sensitive text,
    /// #41). A rejected command must not mutate any state. A rejection is **not**
    /// confirmable: re-submitting with `userConfirmed: true` will not authorize it
    /// (it is a fail-closed read error, or an automated proposal barred by #4).
    case rejected(reason: String)
    /// The command is a destructive change to a critical or imminent alarm that the
    /// user must explicitly confirm (#6). Unlike `.rejected`, re-submitting the same
    /// command with `userConfirmed: true` **will** be authorized. `reason` is the
    /// user-facing prompt. Kept distinct so a caller never offers "confirm & retry"
    /// for a non-confirmable rejection, nor mistakes a fail-closed error for a prompt.
    case needsConfirmation(reason: String)
}
