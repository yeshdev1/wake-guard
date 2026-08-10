import Foundation
import Observation

/// Drives the operational diagnostics screen (WG-230): refreshes a **redacted** snapshot (permissions,
/// reconciliation state, last safe schedule sync, redacted errors) and produces a **user-initiated** export.
/// It only ever reads coarse status; it holds no alarm authority and never surfaces raw sensitive data.
@MainActor
@Observable
final class DiagnosticsModel {
    private(set) var snapshot: DiagnosticsSnapshot?

    private let provider: any DiagnosticsProviding

    init(provider: any DiagnosticsProviding) {
        self.provider = provider
    }

    func refresh() async {
        snapshot = await provider.snapshot()
    }

    /// The current diagnostics as a redacted report — used by the view and the export.
    var report: String? {
        snapshot.map { DiagnosticsRenderer.report($0) }
    }

    /// Prepare a shareable diagnostics export. **User-initiated** — nothing is exported unless this is
    /// called from an explicit tap, and the content is the redacted report (no raw sensitive data).
    func exportReport() -> ShareableExport? {
        guard let report else { return nil }
        return ShareableExport(
            data: Data(report.utf8), suggestedFileName: "WakeGuard-diagnostics.txt")
    }
}
