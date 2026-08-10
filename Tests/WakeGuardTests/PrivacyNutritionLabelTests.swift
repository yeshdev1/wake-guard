import Foundation
import XCTest

@testable import WakeGuard

/// WG-187: App Privacy nutrition-label mapping. Verifies **every data type is accounted for**, that the
/// **only transmitted data is optional + redacted** (all raw data is not collected), that **nothing is
/// linked to identity or used for tracking**, and that the mapping **matches app behavior** — consistent
/// with the WG-186 privacy manifest (no default collection).
final class PrivacyNutritionLabelTests: XCTestCase {

    func testEveryDataTypeIsAccountedFor() {
        for dataType in NutritionDataType.allCases {
            XCTAssertNotNil(
                PrivacyNutritionLabel.entry(for: dataType), "\(dataType) has no nutrition entry")
        }
        XCTAssertEqual(PrivacyNutritionLabel.entries.count, NutritionDataType.allCases.count)
    }

    func testNothingIsLinkedToIdentityOrUsedForTracking() {
        for entry in PrivacyNutritionLabel.entries {
            XCTAssertFalse(
                entry.linkedToIdentity, "\(entry.dataType) must not be linked to identity")
            XCTAssertFalse(entry.usedForTracking, "\(entry.dataType) must not be used for tracking")
            XCTAssertFalse(entry.purpose.isEmpty)
        }
    }

    func testOnlyCloudDerivedSummariesAreTransmittedAndAreRedacted() {
        XCTAssertEqual(PrivacyNutritionLabel.transmittedDataTypes, [.cloudDerivedSummaries])
        for entry in PrivacyNutritionLabel.entries where entry.dataType != .cloudDerivedSummaries {
            XCTAssertEqual(
                entry.collection, .notCollected,
                "\(entry.dataType) raw data must not be transmitted")
        }
        XCTAssertEqual(
            PrivacyNutritionLabel.entry(for: .cloudDerivedSummaries)?.collection, .optionalRedacted)
    }

    // MARK: matches the WG-186 privacy manifest (no default collection)

    func testMappingMatchesManifestNoDefaultCollection() throws {
        // Raw data is not collected by default, so the manifest's collected-data types must be empty.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("PrivacyInfo.xcprivacy"))
        let manifest = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertTrue((manifest["NSPrivacyCollectedDataTypes"] as? [Any] ?? [1]).isEmpty)

        let defaultCollected = PrivacyNutritionLabel.entries.filter {
            $0.collection != .notCollected
        }
        XCTAssertEqual(
            defaultCollected.map(\.dataType), [.cloudDerivedSummaries],
            "only the optional cloud path may deviate from not-collected")
    }
}
