import Foundation

/// The result of processing an `AlarmCommand` (`AlarmCommandProcessor`, WG-027).
enum CommandOutcome: Sendable, Equatable {
    case applied
    case rejected(reason: String)
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
