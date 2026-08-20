import Foundation

/// The outcome of **one** sleep read (WG-319) — the card's counterpart to `MovementSummary`, and
/// deliberately the same shape.
///
/// The distinction it exists to make is between a read that **concluded** and a read that **never
/// happened**. `try?` collapsed both into an empty sample set, so a refresh cancelled by the screen going
/// away, or a query whose completion never arrived, produced the identical value as a revoked grant: "no
/// samples", which the card renders as "There isn't enough sleep data yet…". That is a claim about the
/// user's data, made from a read that returned nothing at all.
///
/// The asymmetry matters in both directions. On a **cold open** there is nothing to preserve, so a
/// nothing-was-read outcome must still resolve the card — `assessment` staying `nil` is the permanent
/// spinner WG-319 exists to remove. On a **warm** screen there is something to preserve, so it must not be
/// overwritten. One value carries both, rather than two policies in a switch: WG-318's round ten found
/// exactly that split on the movement path, where a timeout erased a correct estimate while a cancellation —
/// the same epistemic state — preserved it.
enum SleepReadOutcome: Sendable {
    /// The query concluded and answered. **This is the only case that is a result**, and it is where a
    /// revoked grant arrives: HealthKit does not reveal read denial, so an unauthorized read returns an empty
    /// sample set rather than an error. `ReadinessViewModel` documents that no stale readiness claim survives
    /// a refresh, and that guarantee rests entirely here.
    case samples([SleepSample])

    /// The query concluded by **throwing** — a read error, a database that was inaccessible, an entitlement
    /// fault. Not a result: it learned nothing about the user's sleep, so it is handled exactly as
    /// `.timedOut` is.
    ///
    /// This case previously mapped to `.samples([])`, which rendered a failed read as a data shortage. The
    /// justification was that a revoked grant arrives as a throw and must not leave a stale readiness on
    /// screen — but that premise is false (see `.samples`), and the guarantee it was protecting is carried by
    /// the empty-samples path regardless.
    case failed

    /// The refresh was cancelled before it read anything — **not a result**.
    case cancelled

    /// The deadline won the race before HealthKit answered — also **not a result**, and handled exactly as
    /// `.cancelled` is.
    ///
    /// Its own case rather than reusing `.cancelled`, matching `MovementSummary`: the two paths on this one
    /// screen having the same shape is worth more than saving a case.
    ///
    /// **What this three-way split does *not* buy, though an earlier version of this comment claimed it
    /// would.** `.failed`, `.cancelled` and `.timedOut` are **not distinguishable at any seam**: they share a
    /// single `switch` arm in `ReadinessViewModel.applySleepRead`, that view model is the only consumer, and
    /// nothing observes which of the three arrived. Measured, not reasoned — deleting
    /// `readSamples`' `catch is CancellationError` (so a cancellation becomes `.failed`), or changing
    /// `samplesBeforeDeadline`'s `?? .cancelled` to `?? .failed`, each leaves the whole suite green.
    /// `MovementSummary` collapses its two the same way, so the parity is real rather than aspirational.
    ///
    /// Kept anyway, for the reader rather than the compiler: the cause genuinely differs, and a future
    /// consumer that needs to tell a hung read from a dismissed screen finds the distinction already made.
    /// A reader deciding whether to rely on it should know it is currently unenforced.
    case timedOut
}
