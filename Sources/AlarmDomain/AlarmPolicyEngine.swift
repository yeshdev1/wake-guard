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
    /// #41). A rejected command must not mutate any state.
    case rejected(reason: String)
}
