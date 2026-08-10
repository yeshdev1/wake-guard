import Foundation

/// A coarse area of the app for a crash breadcrumb (WG-221) — a closed enum, never free text.
enum BreadcrumbCategory: String, Sendable, Equatable, Hashable, CaseIterable {
    case alarm, challenge, reconciliation, permission, agent, persistence
}

/// A coarse action for a crash breadcrumb (WG-221) — a closed enum.
enum BreadcrumbAction: String, Sendable, Equatable, Hashable, CaseIterable {
    case started, scheduled, applied, cancelled, failed, recovered, denied
}

/// A crash breadcrumb (WG-221): a **redacted** trail entry. It carries only a coarse category + action and
/// an optional `CorrelationID` that **links to the local audit log** — never the audited data itself. It is
/// structurally incapable of holding raw health, location, calendar, journal, or prompt text.
struct CrashBreadcrumb: Sendable, Equatable, Hashable {
    let category: BreadcrumbCategory
    let action: BreadcrumbAction
    /// Links this crumb to a local audit event; a bare UUID, safe to include in a crash report.
    let correlationID: CorrelationID?

    init(
        _ category: BreadcrumbCategory, _ action: BreadcrumbAction,
        correlationID: CorrelationID? = nil
    ) {
        self.category = category
        self.action = action
        self.correlationID = correlationID
    }

    /// The string that would appear in a crash report — coarse identifiers only.
    var rendered: String {
        let base = "\(category.rawValue).\(action.rawValue)"
        guard let correlationID else { return base }
        return "\(base) audit:\(correlationID.rawValue.uuidString)"
    }
}

/// The crash-diagnostics port (WG-221). It accepts **only** a closed `CrashBreadcrumb`, so a caller can't
/// attach raw data. The default is a no-op; a real crash reporter conforms behind this port.
protocol CrashDiagnostics: Sendable {
    func leaveBreadcrumb(_ breadcrumb: CrashBreadcrumb)
}

/// The default: records nothing (no crash SDK needed to build/run).
struct NoOpCrashDiagnostics: CrashDiagnostics {
    func leaveBreadcrumb(_ breadcrumb: CrashBreadcrumb) {}
}

/// Gates crash diagnostics on the user's **opt-in** (WG-221). When disabled, no breadcrumb is left at all;
/// crash diagnostics are off by default (`AppSettings.crashDiagnosticsEnabled`).
struct GatedCrashDiagnostics: CrashDiagnostics {
    private let underlying: any CrashDiagnostics
    private let isEnabled: @Sendable () -> Bool

    init(underlying: any CrashDiagnostics, isEnabled: @escaping @Sendable () -> Bool) {
        self.underlying = underlying
        self.isEnabled = isEnabled
    }

    func leaveBreadcrumb(_ breadcrumb: CrashBreadcrumb) {
        guard isEnabled() else { return }
        underlying.leaveBreadcrumb(breadcrumb)
    }
}
