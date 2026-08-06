import Foundation

/// The result of processing an `AlarmCommand` (`AlarmCommandProcessor`, WG-027).
enum CommandOutcome: Sendable, Equatable {
    case applied
    case rejected(reason: String)
    /// The policy requires explicit user confirmation before this destructive change to a
    /// critical / imminent alarm applies (#6). Distinct from `.rejected`: re-submitting the
    /// same command with `userConfirmed: true` *will* be authorized. A `.rejected` (fail-closed
    /// read error, or an automated proposal against a critical alarm) is NOT confirmable, so a
    /// caller must never offer a "confirm and retry" for it. `reason` is the user-facing prompt.
    case needsConfirmation(reason: String)
    case failed(reason: String)
    /// Local state was applied, but the external (AlarmKit) outcome is unknown — the
    /// outbox entry is left `.uncertain` for reconciliation to resolve (#10).
    case uncertain
    /// A command the processor does not yet apply and whose non-application **fails
    /// safe** (the alarm keeps its current scheduled state) — e.g. reconcile/recover.
    case noOp
    /// A command the processor does not yet apply and whose non-application would
    /// **discard user intent** (snooze / skip / reschedule an occurrence). Returned
    /// (not `.noOp`) so a caller can never mistake a dropped snooze for success and
    /// must tell the user the alarm is unchanged.
    case unsupported(reason: String)
}
