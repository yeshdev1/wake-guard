import Foundation

/// A read-only operational diagnostics snapshot (WG-230): permission statuses, the last reconciliation
/// result, the last safe schedule sync, and **redacted** recent errors. It carries **no sensitive raw
/// data** — permissions are coarse statuses, and errors are `CrashBreadcrumb`s (closed-enum
/// category/action + an optional audit ID), never raw error text.
struct DiagnosticsSnapshot: Sendable, Equatable {
    let permissions: [ConsentCategoryState]
    let reconciliation: ReconciliationSummary
    let lastScheduleSync: Date?
    let recentErrors: [CrashBreadcrumb]
}

/// Supplies the diagnostics snapshot (WG-230); the composition root assembles it from the consent provider,
/// the last reconcile summary, the last sync time, and recent redacted breadcrumbs.
protocol DiagnosticsProviding: Sendable {
    func snapshot() async -> DiagnosticsSnapshot
}

/// Renders a diagnostics snapshot to a **redacted**, human-readable report (WG-230) — the same text a user
/// may export. It only ever prints coarse statuses, reconcile counts, a timestamp, and breadcrumb markers,
/// so the report can never contain raw health, location, calendar, journal, or prompt text.
enum DiagnosticsRenderer {
    static func report(_ snapshot: DiagnosticsSnapshot, now: Date? = nil) -> String {
        var lines = ["WakeGuard diagnostics"]

        lines.append("Permissions:")
        for state in snapshot.permissions {
            lines.append("  \(state.info.title): \(state.status.rawValue)")
        }

        let reconcile = snapshot.reconciliation
        lines.append(
            "Reconciliation: scheduled \(reconcile.scheduled), cancelled \(reconcile.cancelled), "
                + "failed \(reconcile.failed), uncertain \(reconcile.uncertain)")

        let sync =
            snapshot.lastScheduleSync.map { ISO8601DateFormatter().string(from: $0) } ?? "never"
        lines.append("Last safe schedule sync: \(sync)")

        lines.append("Recent errors (redacted):")
        for error in snapshot.recentErrors { lines.append("  \(error.rendered)") }

        return lines.joined(separator: "\n")
    }
}
