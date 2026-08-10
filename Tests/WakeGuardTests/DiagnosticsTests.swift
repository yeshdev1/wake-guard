import Foundation
import XCTest

@testable import WakeGuard

/// WG-230: operational diagnostics screen. Verifies the report **shows permission status, reconciliation
/// state, last safe schedule sync, and redacted errors**, that it carries **no sensitive raw data** (errors
/// are closed-enum breadcrumbs), and that **export is user-initiated** (nothing exports until the explicit
/// call).
final class DiagnosticsTests: XCTestCase {

    private func snapshot(lastSync: Date? = Date(timeIntervalSince1970: 1_700_000_000))
        -> DiagnosticsSnapshot
    {
        DiagnosticsSnapshot(
            permissions: [
                ConsentCategoryState(info: ConsentCopy.info(for: .alarm), status: .granted),
                ConsentCategoryState(info: ConsentCopy.info(for: .health), status: .denied),
            ],
            reconciliation: ReconciliationSummary(scheduled: 2),
            lastScheduleSync: lastSync,
            recentErrors: [CrashBreadcrumb(.reconciliation, .failed)])
    }

    func testReportShowsPermissionsReconcileSyncAndErrors() {
        let report = DiagnosticsRenderer.report(snapshot())
        XCTAssertTrue(report.contains("Alarms: granted"))
        XCTAssertTrue(report.contains("Health (Sleep): denied"))
        XCTAssertTrue(report.contains("scheduled 2"))
        XCTAssertTrue(report.contains("Last safe schedule sync:"))
        XCTAssertFalse(report.contains("sync: never"), "a sync time was provided")
        XCTAssertTrue(report.contains("reconciliation.failed"), "redacted error breadcrumb")
    }

    func testReportContainsOnlyRedactedCoarseData() {
        // Every error line is a breadcrumb marker (category.action) — no free text is representable.
        let report = DiagnosticsRenderer.report(snapshot())
        for error in snapshot().recentErrors {
            XCTAssertTrue(report.contains(error.rendered))
        }
        // Permissions are coarse statuses, not raw data.
        XCTAssertFalse(report.lowercased().contains("hrv"))
        XCTAssertFalse(report.contains("52.5200"))
    }

    func testNeverSyncedRendersNever() {
        XCTAssertTrue(
            DiagnosticsRenderer.report(snapshot(lastSync: nil)).contains(
                "Last safe schedule sync: never"))
    }

    // MARK: export is user-initiated

    @MainActor
    func testExportIsUserInitiatedAndCarriesTheRedactedReport() async throws {
        let model = DiagnosticsModel(provider: StubDiagnosticsProvider(value: snapshot()))
        XCTAssertNil(model.exportReport(), "nothing to export before a refresh")

        await model.refresh()
        let export = try XCTUnwrap(model.exportReport(), "export only on the explicit call")
        let text = try XCTUnwrap(String(bytes: export.data, encoding: .utf8))
        XCTAssertEqual(text, model.report)
        XCTAssertTrue(export.suggestedFileName.hasSuffix(".txt"))
    }
}

private struct StubDiagnosticsProvider: DiagnosticsProviding {
    let value: DiagnosticsSnapshot
    func snapshot() async -> DiagnosticsSnapshot { value }
}
