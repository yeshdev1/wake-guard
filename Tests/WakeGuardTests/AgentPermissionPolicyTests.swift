import Foundation
import XCTest

@testable import WakeGuard

/// WG-171: the agent-permission modes + policy. Verifies the modes include **recommend-only** and
/// **ask-before-acting**, that **auto-adjust is not selectable** (disabled for the MVP), and — the core
/// safety rule — that a **critical alarm is never changed without confirmation in any mode** (there is no
/// silent-apply action at all). Also pins the backward-compatible persistence in `AppSettings`.
final class AgentPermissionPolicyTests: XCTestCase {

    private let policy = AgentActionPolicy()

    // MARK: modes

    func testSelectableModesAreRecommendOnlyAndAskBeforeActing() {
        XCTAssertEqual(AgentPermissionMode.selectable, [.recommendOnly, .askBeforeActing])
        XCTAssertFalse(AgentPermissionMode.autoAdjust.isSelectable)
        XCTAssertTrue(AgentPermissionMode.recommendOnly.isSelectable)
        XCTAssertTrue(AgentPermissionMode.askBeforeActing.isSelectable)
    }

    // MARK: per-mode action (non-critical)

    func testRecommendOnlyNeverActs() {
        XCTAssertEqual(policy.action(mode: .recommendOnly, targetIsCritical: false), .recommendOnly)
    }

    func testAskBeforeActingRequestsConfirmation() {
        XCTAssertEqual(
            policy.action(mode: .askBeforeActing, targetIsCritical: false), .requestConfirmation)
    }

    func testAutoAdjustIsBoundedToConfirmationNeverSilent() {
        // Even if somehow set, auto-adjust never applies silently — it is bounded to confirmation (ADR).
        XCTAssertEqual(
            policy.action(mode: .autoAdjust, targetIsCritical: false), .requestConfirmation)
    }

    // MARK: critical alarms remain immutable without confirmation (#6)

    func testCriticalTargetIsNeverAppliedSilentlyInAnyMode() {
        for mode in AgentPermissionMode.allCases {
            let action = policy.action(mode: mode, targetIsCritical: true)
            // The only actions are recommend-only (never applies) and request-confirmation (asks first);
            // there is no auto-apply, so a critical alarm can never change without confirmation.
            switch action {
            case .recommendOnly:
                XCTAssertEqual(mode, .recommendOnly)
            case .requestConfirmation:
                XCTAssertNotEqual(mode, .recommendOnly)
            }
        }
    }

    func testCriticalRequestsConfirmationForActingModes() {
        XCTAssertEqual(
            policy.action(mode: .askBeforeActing, targetIsCritical: true), .requestConfirmation)
        XCTAssertEqual(
            policy.action(mode: .autoAdjust, targetIsCritical: true), .requestConfirmation)
    }

    // MARK: AppSettings persistence (backward compatible)

    func testDefaultAgentModeIsRecommendOnly() {
        XCTAssertEqual(AppSettings.default.agentPermissionMode, .recommendOnly)
    }

    func testDecodesLegacyBlobWithoutAgentMode() throws {
        // A settings blob written before WG-171 (no agentPermissionMode key) must still decode.
        let legacy = #"""
            {"preAlarmPromptEnabled":false,"automaticProposalPreparationEnabled":false,
             "cloudAIEnabled":false,"locationContextEnabled":false,"readinessScoreEnabled":false,
             "experimentalAntiCheatEnabled":false,"analyticsEnabled":false,
             "smartFeaturesKillSwitch":false}
            """#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(settings.agentPermissionMode, .recommendOnly)
    }

    func testRoundTripsAgentMode() throws {
        var settings = AppSettings.default
        settings.agentPermissionMode = .askBeforeActing
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.agentPermissionMode, .askBeforeActing)
        XCTAssertEqual(decoded, settings)
    }
}
