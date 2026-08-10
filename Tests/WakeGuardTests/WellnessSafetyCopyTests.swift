import XCTest

@testable import WakeGuard

/// WG-128: wellness disclaimers + safety copy. Verifies the app **identifies wellness, not medical,
/// scope**, that **urgent symptoms are routed away from the AI** (a conservative pre-filter that errs
/// toward referral, catches indirect crisis + third-party emergency phrasings, and gives the
/// mental-health-crisis path its own warmer copy), and that the copy is clear.
final class WellnessSafetyCopyTests: XCTestCase {

    // MARK: wellness, not medical, scope

    func testScopeCopyIdentifiesWellnessNotMedical() {
        let scope = WellnessSafetyCopy.scope.lowercased()
        XCTAssertTrue(scope.contains("wellness"))
        XCTAssertTrue(scope.contains("not medical advice"))
        XCTAssertTrue(
            scope.contains("does not diagnose, treat, or prevent"),
            "explicitly disclaims diagnosis/treatment/prevention (#39)")
    }

    func testEstimatesAreDescribedAsNonClinical() {
        let text = WellnessSafetyCopy.estimatesNotClinical.lowercased()
        XCTAssertTrue(text.contains("estimate"))
        XCTAssertTrue(text.contains("not clinical measurements"))
    }

    // MARK: urgent symptoms are not handled by the AI

    func testMedicalEmergencyCopyPointsToAProfessionalAndEmergencyServices() {
        let text = WellnessSafetyCopy.urgentSymptoms.lowercased()
        XCTAssertTrue(text.contains("won't try to"), "states the assistant won't handle it")
        XCTAssertTrue(text.contains("healthcare professional"))
        XCTAssertTrue(text.contains("emergency"))
    }

    func testPhysicalEmergencyTextRoutesToTheMedicalReferral() {
        let cases = [
            "I have chest pain and can't breathe", "I think I'm having a heart attack",
            "he's not breathing", "she passed out", "he collapsed and is unresponsive",
            "this is an emergency", "she's having an allergic reaction",
        ]
        for text in cases {
            XCTAssertEqual(
                UrgentSymptomPolicy.scope(of: text), .referral(.medicalEmergency),
                "physical-emergency text → medical referral, never the assistant: \(text)")
        }
    }

    func testIndirectCrisisPhrasingsRouteToTheCrisisReferral() {
        // The dangerous direction is a false negative — common indirect ideation must still be caught.
        let cases = [
            "I want to kill myself", "I don't want to be here anymore", "I want to die",
            "I'd be better off dead", "I want to hurt myself", "I want to end it all",
        ]
        for text in cases {
            XCTAssertEqual(
                UrgentSymptomPolicy.scope(of: text), .referral(.mentalHealthCrisis),
                "crisis phrasing → crisis referral, never the assistant: \(text)")
        }
    }

    func testUrgentDetectionIsCaseInsensitive() {
        XCTAssertEqual(UrgentSymptomPolicy.scope(of: "CHEST PAIN"), .referral(.medicalEmergency))
    }

    func testOrdinaryWellnessTextStaysInScope() {
        // Includes the deliberate negative case: "dead tired" must NOT trip the crisis gate.
        let benign = [
            "help me set a bedtime", "why am I tired in the mornings",
            "how did I sleep last night", "I'm dead tired this morning", "",
        ]
        for text in benign {
            XCTAssertEqual(
                UrgentSymptomPolicy.scope(of: text), .wellness,
                "ordinary wellness text stays in scope")
        }
    }

    // MARK: the crisis path gets its own, warmer copy

    func testCrisisReferralCopyIsDistinctWarmAndPointsToSupport() {
        let crisis = WellnessSafetyCopy.mentalHealthCrisis
        XCTAssertNotEqual(
            crisis, WellnessSafetyCopy.urgentSymptoms, "the crisis path has its own copy")
        let lowered = crisis.lowercased()
        XCTAssertTrue(lowered.contains("crisis line"), "points to a crisis resource")
        XCTAssertTrue(lowered.contains("don't have to face it alone"), "non-dismissive")
        XCTAssertTrue(
            lowered.contains("emergency services"), "still points to emergency help if needed")
    }

    func testReferralCopyMapsToTheRightKind() {
        XCTAssertEqual(
            UrgentSymptomPolicy.referralCopy(for: .medicalEmergency),
            WellnessSafetyCopy.urgentSymptoms)
        XCTAssertEqual(
            UrgentSymptomPolicy.referralCopy(for: .mentalHealthCrisis),
            WellnessSafetyCopy.mentalHealthCrisis)
    }
}
