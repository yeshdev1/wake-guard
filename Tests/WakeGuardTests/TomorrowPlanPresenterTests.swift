import Foundation
import XCTest

@testable import WakeGuard

/// WG-146: the tomorrow-plan recommendation. Verifies the **existing alarm remains visible** (always
/// exposed, even without a recommendation), that the **recommendation shows its reason and buffers**, and
/// that **applying requires an explicit action** — the presentation carries no apply/mutation (the view's
/// button is the only path).
final class TomorrowPlanPresenterTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let profile = MorningPreparationProfile.default  // 45 / 30 / 10 min

    private func plan(
        drivenByImportant: Bool = true, hasLocation: Bool = false,
        confidence: WakePlanConfidence = .high,
        hasConflicts: Bool = false, wake: Date? = nil, count: Int = 1
    ) -> LatestSafeWakePlan {
        LatestSafeWakePlan(
            latestSafeWake: wake ?? base.addingTimeInterval(3_600),
            bindingEventStart: base.addingTimeInterval(7_200),
            drivenByConfirmedImportant: drivenByImportant,
            appliedLeadTime: 3_600, bindingHasLocation: hasLocation, confidence: confidence,
            consideredEventCount: count, hasConflicts: hasConflicts)
    }

    private func present(_ plan: LatestSafeWakePlan?, existingAlarmRing: Date?)
        -> TomorrowPlanPresentation
    {
        TomorrowPlanPresenter.present(
            plan: plan, profile: profile, existingAlarmRing: existingAlarmRing)
    }

    // MARK: existing alarm remains visible

    func testExistingAlarmIsAlwaysExposedEvenWithoutARecommendation() {
        let ring = base.addingTimeInterval(1_000)
        XCTAssertEqual(present(plan(), existingAlarmRing: ring).existingAlarmRing, ring)
        let noPlan = present(nil, existingAlarmRing: ring)
        XCTAssertEqual(
            noPlan.existingAlarmRing, ring, "the existing alarm is shown even with no plan")
        XCTAssertNil(noPlan.recommendation)
    }

    // MARK: recommendation shows reason + buffers

    func testRecommendationCarriesReasonAndBuffers() throws {
        let recommendation = try XCTUnwrap(
            present(plan(hasLocation: true), existingAlarmRing: nil).recommendation)
        XCTAssertFalse(recommendation.reason.isEmpty)
        let labels = recommendation.buffers.map(\.label)
        XCTAssertEqual(
            labels, ["Getting ready", "Travel", "Safety margin"], "travel shown for a located event"
        )
        XCTAssertEqual(
            recommendation.buffers.map(\.minutes), [45, 30, 10], "buffer minutes from the profile")
    }

    func testTravelBufferIsHiddenWithoutALocation() throws {
        let recommendation = try XCTUnwrap(
            present(plan(hasLocation: false), existingAlarmRing: nil).recommendation)
        XCTAssertEqual(recommendation.buffers.map(\.label), ["Getting ready", "Safety margin"])
    }

    func testReasonReflectsWhetherTheEventWasConfirmedImportant() throws {
        let confirmed = try XCTUnwrap(
            present(plan(drivenByImportant: true), existingAlarmRing: nil).recommendation)
        XCTAssertTrue(confirmed.reason.lowercased().contains("marked as important"))
        let inferred = try XCTUnwrap(
            present(plan(drivenByImportant: false, confidence: .moderate), existingAlarmRing: nil)
                .recommendation)
        XCTAssertTrue(inferred.reason.lowercased().contains("rough guess"))
    }

    // MARK: differs-from-existing

    func testDiffersFromExistingAlarm() throws {
        let wake = base.addingTimeInterval(3_600)
        let same = try XCTUnwrap(
            present(plan(wake: wake), existingAlarmRing: wake).recommendation)
        XCTAssertFalse(same.differsFromExistingAlarm, "an alarm at the same time doesn't differ")
        let different = try XCTUnwrap(
            present(plan(wake: wake), existingAlarmRing: wake.addingTimeInterval(1_800))
                .recommendation)
        XCTAssertTrue(different.differsFromExistingAlarm)
        let noAlarm = try XCTUnwrap(
            present(plan(wake: wake), existingAlarmRing: nil).recommendation)
        XCTAssertTrue(
            noAlarm.differsFromExistingAlarm, "no existing alarm → there's something to apply")
    }

    // MARK: apply requires explicit action

    func testPresentationCarriesNoApplyAction() {
        // The presentation is display data only — its fields are the existing alarm + the recommendation,
        // nothing that applies/mutates an alarm. Applying is the view's explicit button (#6-gated in
        // composition).
        let mirror = Mirror(reflecting: present(plan(), existingAlarmRing: nil))
        XCTAssertEqual(
            Set(mirror.children.compactMap(\.label)), ["existingAlarmRing", "recommendation"])
    }
}
