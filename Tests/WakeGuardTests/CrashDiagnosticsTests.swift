import Foundation
import XCTest

@testable import WakeGuard

/// WG-221: crash diagnostics redaction. Verifies **breadcrumbs contain no raw sensitive data** (only coarse
/// closed-enum identifiers), that **correlation IDs link to the local audit safely** (a bare UUID, not the
/// audited data), and that the user **can opt out** (gated off records nothing; off by default).
final class CrashDiagnosticsTests: XCTestCase {

    func testBreadcrumbCarriesOnlyCoarseIdentifiers() {
        let crumb = CrashBreadcrumb(.alarm, .scheduled)
        let fields = Set(Mirror(reflecting: crumb).children.compactMap(\.label))
        XCTAssertEqual(fields, ["category", "action", "correlationID"])
        // No free-text field could hold sensitive data.
        for forbidden in ["message", "detail", "text", "payload"] {
            XCTAssertFalse(fields.contains(forbidden))
        }
        XCTAssertEqual(crumb.rendered, "alarm.scheduled")
    }

    func testCorrelationIDLinksToLocalAuditSafely() throws {
        let id = CorrelationID(
            try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")))
        let crumb = CrashBreadcrumb(.agent, .applied, correlationID: id)
        // The crumb references the audit event by ID — enough to correlate, but it carries none of the
        // audit's sensitive content.
        XCTAssertTrue(crumb.rendered.contains(id.rawValue.uuidString))
        XCTAssertTrue(crumb.rendered.hasPrefix("agent.applied"))
    }

    func testRenderedBreadcrumbsNeverContainArbitraryText() {
        // Whatever the category/action, the rendered crumb is only enum words (+ an audit UUID) — there is
        // no way to inject sensitive text, since the API takes closed enums.
        for category in BreadcrumbCategory.allCases {
            for action in BreadcrumbAction.allCases {
                let rendered = CrashBreadcrumb(category, action).rendered
                XCTAssertEqual(rendered, "\(category.rawValue).\(action.rawValue)")
            }
        }
    }

    // MARK: opt out

    func testDisabledCrashDiagnosticsLeavesNoBreadcrumb() {
        let spy = RecordingCrashDiagnostics()
        let gated = GatedCrashDiagnostics(underlying: spy, isEnabled: { false })
        gated.leaveBreadcrumb(CrashBreadcrumb(.alarm, .failed))
        XCTAssertTrue(spy.breadcrumbs.isEmpty)
    }

    func testEnabledCrashDiagnosticsLeavesBreadcrumb() {
        let spy = RecordingCrashDiagnostics()
        let gated = GatedCrashDiagnostics(underlying: spy, isEnabled: { true })
        gated.leaveBreadcrumb(CrashBreadcrumb(.reconciliation, .recovered))
        XCTAssertEqual(spy.breadcrumbs, [CrashBreadcrumb(.reconciliation, .recovered)])
    }

    func testCrashDiagnosticsAreOffByDefault() {
        XCTAssertFalse(AppSettings.default.crashDiagnosticsEnabled)
    }

    func testLegacySettingsBlobDefaultsCrashDiagnosticsOff() throws {
        let legacy = #"""
            {"preAlarmPromptEnabled":false,"automaticProposalPreparationEnabled":false,
             "cloudAIEnabled":false,"locationContextEnabled":false,"readinessScoreEnabled":false,
             "experimentalAntiCheatEnabled":false,"analyticsEnabled":false,
             "smartFeaturesKillSwitch":false}
            """#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertFalse(settings.crashDiagnosticsEnabled)
    }
}

private final class RecordingCrashDiagnostics: CrashDiagnostics {
    private let box = Synchronized<[CrashBreadcrumb]>([])
    var breadcrumbs: [CrashBreadcrumb] { box.get() }
    func leaveBreadcrumb(_ breadcrumb: CrashBreadcrumb) { box.mutate { $0.append(breadcrumb) } }
}
