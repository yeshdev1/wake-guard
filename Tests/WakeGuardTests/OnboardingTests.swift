import XCTest

@testable import WakeGuard

/// WG-200: progressive onboarding. Verifies **only alarm essentials are requested initially**, that
/// **optional permissions are feature-triggered** (never at onboarding), and that **skip paths remain
/// useful** — skipping the first alarm still completes onboarding into a usable app.
final class OnboardingTests: XCTestCase {

    // MARK: essentials only, optional deferred

    func testOnboardingRequestsOnlyAlarmEssentials() {
        XCTAssertEqual(OnboardingPlan.essentials, [.alarm, .notifications])
        for optional in [ConsentCategory.motion, .location, .health, .calendar, .cloudAI] {
            XCTAssertFalse(
                OnboardingPlan.isRequestedAtOnboarding(optional),
                "\(optional) must not be requested during onboarding")
        }
    }

    func testOptionalPermissionsAreFeatureTriggered() {
        XCTAssertEqual(
            OnboardingPlan.featureTriggered, [.motion, .location, .health, .calendar, .cloudAI])
    }

    func testEssentialsAndFeatureTriggeredPartitionAllCategories() {
        let essentials = Set(OnboardingPlan.essentials)
        let featureTriggered = Set(OnboardingPlan.featureTriggered)
        XCTAssertTrue(essentials.isDisjoint(with: featureTriggered))
        XCTAssertEqual(essentials.union(featureTriggered), Set(ConsentCategory.allCases))
    }

    // MARK: flow + skip

    @MainActor
    func testFlowAdvancesThroughEssentialsToReady() {
        let model = OnboardingModel()
        XCTAssertEqual(model.step, .welcome)
        model.advance()
        XCTAssertEqual(model.step, .enableAlarms)
        model.advance()
        XCTAssertEqual(model.step, .createFirstAlarm)
        model.advance()
        XCTAssertEqual(model.step, .ready)
        XCTAssertTrue(model.isComplete)
    }

    @MainActor
    func testFirstAlarmIsSkippableAndStillCompletes() {
        let model = OnboardingModel()
        model.advance()  // enableAlarms
        model.advance()  // createFirstAlarm
        XCTAssertTrue(model.canSkip)
        model.skip()
        XCTAssertTrue(model.skippedFirstAlarm)
        XCTAssertEqual(model.step, .ready)
        XCTAssertTrue(model.isComplete, "skipping the first alarm still completes onboarding")
    }

    @MainActor
    func testWelcomeAndReadyCannotBeSkipped() {
        let model = OnboardingModel()
        XCTAssertFalse(model.canSkip)  // welcome
        model.skip()
        XCTAssertEqual(model.step, .welcome, "skip is a no-op on a non-skippable step")
    }

    func testOnlyCreateFirstAlarmIsSkippable() {
        for step in OnboardingStep.allCases {
            XCTAssertEqual(step.isSkippable, step == .createFirstAlarm)
        }
    }
}
