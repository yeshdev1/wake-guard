import XCTest

@testable import WakeGuard

/// WG-061: the Motion & Fitness permission flow for the walk challenge. Verifies the request is
/// made **in context** (only on an explicit request, never on reading state), that authorization
/// grants the walk challenge, that **every** non-authorized outcome (denied / restricted /
/// interrupted) routes to the accessible alternative so the user is never trapped (#21), and that
/// the purpose copy is specific and honest.
final class MotionAuthorizationFlowTests: XCTestCase {

    private func coordinator(_ authorizer: FakeMotionAuthorizer)
        -> MotionChallengeAuthorizationCoordinator
    {
        MotionChallengeAuthorizationCoordinator(authorizer: authorizer)
    }

    func testCurrentStepRoutesEachStatus() async {
        let cases: [(MotionAuthorizationStatus, MotionChallengeAuthorizationStep)] = [
            (.notDetermined, .explainThenRequest),
            (.authorized, .useWalkChallenge),
            (.denied, .useAccessibleAlternativeOfferSettings),
            (.restricted, .useAccessibleAlternative),
        ]
        for (status, expected) in cases {
            let step = await coordinator(FakeMotionAuthorizer(status: status)).currentStep()
            XCTAssertEqual(step, expected, "status \(status)")
        }
    }

    func testReadingTheStepNeverTriggersARequest() async {
        // In context: the system dialog only appears on an explicit request, not on reading state.
        let authorizer = FakeMotionAuthorizer(status: .notDetermined)
        _ = await coordinator(authorizer).currentStep()
        let count = await authorizer.requestCallCount
        XCTAssertEqual(count, 0, "reading the step must not prompt")
    }

    func testRequestGrantsThenUsesWalkChallenge() async {
        let authorizer = FakeMotionAuthorizer(status: .notDetermined, afterRequest: .authorized)
        let step = await coordinator(authorizer).requestAfterExplanation()
        XCTAssertEqual(step, .useWalkChallenge)
        let count = await authorizer.requestCallCount
        XCTAssertEqual(count, 1, "the request is made once")
    }

    func testRequestDeniedOffersAccessibleAlternative() async {
        let authorizer = FakeMotionAuthorizer(status: .notDetermined, afterRequest: .denied)
        let step = await coordinator(authorizer).requestAfterExplanation()
        XCTAssertEqual(step, .useAccessibleAlternativeOfferSettings)
    }

    func testInterruptedRequestFallsBackToAccessibleAlternative() async {
        // An interrupted request must never trap the user — the accessible alternative always works.
        let authorizer = FakeMotionAuthorizer(status: .notDetermined, requestThrows: true)
        let step = await coordinator(authorizer).requestAfterExplanation()
        XCTAssertEqual(step, .useAccessibleAlternative)
    }

    func testPurposeCopyIsSpecificAndHonest() {
        let copy = MotionChallengePurpose.explanation
        XCTAssertTrue(copy.localizedCaseInsensitiveContains("Motion & Fitness"))
        XCTAssertTrue(copy.localizedCaseInsensitiveContains("walk"), "names the specific use")
        XCTAssertTrue(
            copy.localizedCaseInsensitiveContains("steps")
                || copy.localizedCaseInsensitiveContains("movement"))
        XCTAssertTrue(
            copy.localizedCaseInsensitiveContains("tap")
                || copy.localizedCaseInsensitiveContains("press"),
            "discloses the accessible alternative")
        XCTAssertTrue(
            copy.localizedCaseInsensitiveContains("never your location"),
            "explicitly disclaims location use (#41 honesty)")
    }

    func testRequestRestrictedUsesAccessibleAlternative() async {
        let authorizer = FakeMotionAuthorizer(status: .notDetermined, afterRequest: .restricted)
        let step = await coordinator(authorizer).requestAfterExplanation()
        XCTAssertEqual(step, .useAccessibleAlternative)
    }

    func testStillNotDeterminedAfterRequestDoesNotLoop() async {
        // An anomalous still-not-determined result after a request must not re-prompt (no loop) —
        // it falls back to the always-available alternative.
        let authorizer = FakeMotionAuthorizer(status: .notDetermined, afterRequest: .notDetermined)
        let step = await coordinator(authorizer).requestAfterExplanation()
        XCTAssertEqual(step, .useAccessibleAlternative)
    }

    func testUnknownStatusFailsToDecode() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(MotionAuthorizationStatus.self, from: Data("\"granted\"".utf8))
        )
    }
}
