import Foundation

extension AppEnvironment {
    /// Wrap the processor so every `reconcile()` records into a fresh `LastReconcileStore`, returning both
    /// (the store feeds the diagnostics provider). Kept as a helper so `make` stays within its budget.
    static func makeRecordingProcessor(
        wrapping processor: any AlarmCommandProcessing, clock: any WallClock
    ) -> (processor: any AlarmCommandProcessing, reconcileStore: LastReconcileStore) {
        let store = LastReconcileStore()
        return (
            RecordingAlarmCommandProcessor(wrapped: processor, store: store, clock: clock), store
        )
    }
}

/// The last reconciliation result + last safe schedule sync (WG-230). Written by every `reconcile()` (via
/// `RecordingAlarmCommandProcessor`) and read by the diagnostics provider, so the diagnostics screen can
/// surface a support-visible sync signal instead of discarding the summary.
actor LastReconcileStore {
    private var lastSummary: ReconciliationSummary?
    private var lastSync: Date?

    func record(_ summary: ReconciliationSummary, at time: Date) {
        lastSummary = summary
        // "Last safe schedule sync" = the last time a reconcile actually ran against ground truth; a
        // `skipped` pass (ground truth/desired unreadable, #10) is not a sync.
        if !summary.skipped { lastSync = time }
    }

    func current() -> ReconcileState {
        ReconcileState(summary: lastSummary ?? ReconciliationSummary(), lastSync: lastSync)
    }
}

/// The last reconcile summary + last successful sync time — the value `LastReconcileStore` exposes.
struct ReconcileState: Sendable, Equatable {
    let summary: ReconciliationSummary
    let lastSync: Date?
}

/// Wraps the command processor to record the result of every `reconcile()` for diagnostics (WG-230),
/// delegating `process` unchanged. Transparent to callers — it is the same `AlarmCommandProcessing`, so it
/// adds no authority and changes no behavior; it only observes reconcile outcomes.
struct RecordingAlarmCommandProcessor: AlarmCommandProcessing {
    let wrapped: any AlarmCommandProcessing
    let store: LastReconcileStore
    let clock: any WallClock

    func process(
        _ command: AlarmCommand, from source: CommandSource, by actor: AuditActor,
        userConfirmed: Bool
    ) async -> CommandOutcome {
        await wrapped.process(
            command, from: source, by: actor, userConfirmed: userConfirmed)
    }

    func reconcile() async -> ReconciliationSummary {
        let summary = await wrapped.reconcile()
        await store.record(summary, at: clock.now)
        return summary
    }
}

/// The production `DiagnosticsProviding` (WG-230): assembles the read-only snapshot from the consent
/// provider (permission statuses), the last-reconcile store (reconcile summary + last sync), and — for now —
/// no recent breadcrumbs (the redacted crash-breadcrumb ring buffer is a follow-up; the renderer handles an
/// empty list). Carries no sensitive raw data.
struct DefaultDiagnosticsProvider: DiagnosticsProviding {
    let consent: any ConsentStatusProviding
    let reconcile: LastReconcileStore

    func snapshot() async -> DiagnosticsSnapshot {
        var permissions: [ConsentCategoryState] = []
        for info in ConsentCopy.allInfo {
            permissions.append(
                ConsentCategoryState(info: info, status: await consent.status(for: info.category)))
        }
        let state = await reconcile.current()
        return DiagnosticsSnapshot(
            permissions: permissions, reconciliation: state.summary,
            lastScheduleSync: state.lastSync, recentErrors: [])
    }
}
