#if DEBUG
    import Foundation

    /// A `SleepSampleQuerying` that always throws, composed only by the `-uiTestingSleepReadFails` launch
    /// argument (WG-322) so the screenshot tour can reach the readiness card's **`.unavailable`** branch.
    ///
    /// That branch is where the **M4** mutant lived in WG-319 round fourteen — rewriting
    /// `ReadinessDisplayState.cardContent`'s arm to `return nil` restored the permanent spinner, the hidden
    /// card and the hidden always-on movement section while all 1435 tests passed. **M4 is no longer the
    /// gap:** round fourteen killed it with `ReadinessDisplayStateTests`, inside `ci-fast`. What no unit
    /// test can reach is the seam that *consumes* the property — the `if let content =
    /// model.readiness.cardContent` at `ReadinessScreen.swift:51`, whose re-gating on `assessment != nil`
    /// survives the whole unit target. The branch is unreachable from the ordinary `-uiTesting` graph, whose
    /// `UnavailableSleepQuery` returns `[]` — a concluded read with no samples, which is `.assessed`.
    ///
    /// **It throws rather than hanging.** `ReadinessViewModel.applySleepRead` routes `.failed`, `.cancelled`
    /// and `.timedOut` into the *same* arm, so a thrown error lands on the identical branch as an expired
    /// deadline, instantly and deterministically. A never-answering query would reach it too, but only after
    /// `sleepTimeout` — 15s the tour would have to wait, and the graph has no seam to shorten it, since
    /// `ReadinessScreenContent` builds its view model with the default. The deadline itself is covered at the
    /// unit layer; what was uncovered is the *rendering*, and that is what this reaches.
    ///
    /// Deliberately **additive**: `UnavailableSleepQuery` stays the default, because a graph that could only
    /// fail would delete `testTour4ReadinessDegraded`'s success coverage — the "a double that can only fail
    /// can only document failure" defect WG-318 round nine removed from the motion side.
    struct FailingSleepQuery: SleepSampleQuerying {
        /// Stands in for an `HKSampleQuery` that errors. The card renders one sentence about the *read* for
        /// every failure cause, so the payload is never shown and carries no detail worth asserting on.
        struct ReadFailed: Error {}

        func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
            // Cancellation first, matching the port's stated contract and both real adapters, which wrap
            // their continuation in `withTaskCancellationHandler` and resume with `CancellationError`.
            // Inert on this path today — `applySleepRead` routes `.cancelled` and `.failed` into one arm —
            // but a double that cooperates *less* than production is how an inert fix gets licensed, and
            // this is now the app target's only sleep-failure stand-in.
            try Task.checkCancellation()
            throw ReadFailed()
        }
    }
#endif
