import Foundation
import XCTest

@testable import WakeGuard

/// WG-230: the production diagnostics wiring — the recording processor captures every reconcile's result,
/// and the provider assembles a redacted snapshot (permissions + last reconcile + last safe sync).
final class DiagnosticsWiringTests: XCTestCase {

    /// A minimal `AlarmCommandProcessing` returning a fixed reconcile summary; `process` is inert.
    private struct StubProcessor: AlarmCommandProcessing {
        let summary: ReconciliationSummary
        func process(
            _ command: AlarmCommand, from source: CommandSource, by actor: AuditActor,
            userConfirmed: Bool
        ) async -> CommandOutcome { .noOp }
        func reconcile() async -> ReconciliationSummary { summary }
    }

    func testRecorderCapturesReconcileSummaryAndSync() async {
        let store = LastReconcileStore()
        let recorder = RecordingAlarmCommandProcessor(
            wrapped: StubProcessor(summary: ReconciliationSummary(scheduled: 2)), store: store,
            clock: TestClock(now: Date(timeIntervalSince1970: 1000)))

        let summary = await recorder.reconcile()

        XCTAssertEqual(summary, ReconciliationSummary(scheduled: 2), "reconcile() passes through")
        let state = await store.current()
        XCTAssertEqual(
            state.summary, ReconciliationSummary(scheduled: 2), "the summary is recorded")
        XCTAssertEqual(
            state.lastSync, Date(timeIntervalSince1970: 1000), "the sync time is stamped")
    }

    func testSkippedReconcileIsNotASafeSync() async {
        let store = LastReconcileStore()
        await store.record(
            ReconciliationSummary(skipped: true), at: Date(timeIntervalSince1970: 5000))
        let state = await store.current()
        XCTAssertEqual(state.summary, ReconciliationSummary(skipped: true))
        XCTAssertNil(state.lastSync, "a skipped reconcile (ground truth unreadable) is not a sync")
    }

    func testProviderAssemblesPermissionsAndReconcile() async {
        let store = LastReconcileStore()
        await store.record(
            ReconciliationSummary(scheduled: 1), at: Date(timeIntervalSince1970: 2000))
        let provider = DefaultDiagnosticsProvider(
            consent: FixedConsentStatusProvider(status: .granted), reconcile: store)

        let snapshot = await provider.snapshot()

        XCTAssertEqual(
            snapshot.permissions.count, ConsentCategory.allCases.count,
            "the snapshot lists every permission category")
        XCTAssertTrue(snapshot.permissions.allSatisfy { $0.status == .granted })
        XCTAssertEqual(snapshot.reconciliation, ReconciliationSummary(scheduled: 1))
        XCTAssertEqual(snapshot.lastScheduleSync, Date(timeIntervalSince1970: 2000))
        XCTAssertTrue(
            snapshot.recentErrors.isEmpty, "no breadcrumb buffer wired yet — empty, not raw")
    }
}
