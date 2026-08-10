import XCTest

@testable import WakeGuard

/// WG-120: the wellness data-minimization plan. Verifies **each requested HealthKit type has a
/// user-facing purpose**, that **retention and local processing are defined** (compute-and-discard,
/// on-device), and that **cloud exclusion is explicit** — indeed *structural*: the plan literally cannot
/// express cloud processing or a write. Also pins that the MVP set is minimal (sleep only) and that no
/// purpose makes a medical claim (#39).
final class WellnessDataMinimizationPlanTests: XCTestCase {

    private let plan = WellnessDataMinimizationPlan.mvp

    // MARK: minimal, purposeful set

    func testMVPPlanRequestsOnlySleepAnalysis() {
        XCTAssertEqual(plan.requestedTypes, [.sleepAnalysis])
        XCTAssertFalse(plan.entries.isEmpty)
        XCTAssertEqual(
            Set(plan.requestedTypes).count, plan.requestedTypes.count, "no duplicate requests")
    }

    func testEveryRequestedTypeHasAUserFacingPurpose() {
        for entry in plan.entries {
            XCTAssertFalse(
                entry.userFacingPurpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(entry.type) must carry a user-facing purpose")
        }
    }

    func testRequestedTypesAreAllKnownTypes() {
        XCTAssertTrue(Set(plan.requestedTypes).isSubset(of: Set(WellnessHealthType.allCases)))
    }

    // MARK: retention + local processing are defined

    func testEveryEntryIsReadOnlyOnDeviceComputeAndDiscard() {
        for entry in plan.entries {
            XCTAssertEqual(entry.access, .read, "\(entry.type) is read-only")
            XCTAssertEqual(
                entry.processing, .onDeviceOnly, "\(entry.type) is processed on device only")
            XCTAssertEqual(
                entry.retention, .computeAndDiscard, "\(entry.type) raw samples are not retained")
        }
    }

    // MARK: cloud exclusion is explicit AND structural

    func testEveryEntryIsCloudExcluded() {
        XCTAssertTrue(plan.entries.allSatisfy(\.isCloudExcluded))
    }

    func testCloudProcessingIsStructurallyInexpressible() {
        // The only processing locality is on-device — a cloud value cannot be constructed (#35).
        XCTAssertEqual(ProcessingLocality.allCases, [.onDeviceOnly])
    }

    func testWriteAccessAndRawRetentionAreStructurallyConstrained() {
        XCTAssertEqual(WellnessAccessMode.allCases, [.read], "no write access can be expressed")
        XCTAssertEqual(
            WellnessRetention.allCases, [.computeAndDiscard],
            "raw retention is compute-and-discard only")
    }

    // MARK: no medical claim (#39)

    func testNoPurposeMakesAMedicalClaim() {
        let claimTokens = ["diagnose", "treatment", "disorder", "medical condition", "cure "]
        for entry in plan.entries {
            let purpose = entry.userFacingPurpose.lowercased()
            for token in claimTokens {
                XCTAssertFalse(
                    purpose.contains(token), "\(entry.type) purpose makes a medical claim: \(token)"
                )
            }
        }
    }

    func testSleepPurposeIsFramedAsAnEstimateWithADisclaimer() throws {
        let sleep = try XCTUnwrap(plan.entry(for: .sleepAnalysis))
        XCTAssertEqual(sleep.type, .sleepAnalysis)
        XCTAssertTrue(sleep.userFacingPurpose.lowercased().contains("estimate"))
        XCTAssertTrue(sleep.userFacingPurpose.lowercased().contains("never a diagnosis"))
    }

    // MARK: persistence

    func testPlanRoundTripsThroughCodable() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(
                WellnessDataMinimizationPlan.self, from: try JSONEncoder().encode(plan)),
            plan)
    }
}
