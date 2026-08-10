import XCTest

@testable import WakeGuard

/// WG-180: the permission & consent center. Verifies the seven capabilities are **separate** categories,
/// that **each shows a purpose and revocation guidance**, and that the view-model surfaces the **current
/// status** per category.
final class ConsentCenterTests: XCTestCase {

    func testTheSevenCapabilitiesAreSeparateCategories() {
        XCTAssertEqual(
            ConsentCategory.allCases,
            [.alarm, .notifications, .motion, .location, .health, .calendar, .cloudAI])
    }

    func testEveryCategoryHasATitlePurposeAndRevocationGuidance() {
        for category in ConsentCategory.allCases {
            let info = ConsentCopy.info(for: category)
            XCTAssertFalse(info.title.isEmpty, "\(category) title")
            XCTAssertFalse(info.purpose.isEmpty, "\(category) purpose")
            XCTAssertFalse(info.revocationGuidance.isEmpty, "\(category) revocation guidance")
        }
    }

    func testAlarmAndNotificationsAreCoreTheRestOptional() {
        XCTAssertFalse(ConsentCopy.info(for: .alarm).isOptional)
        XCTAssertFalse(ConsentCopy.info(for: .notifications).isOptional)
        for category in [ConsentCategory.motion, .location, .health, .calendar, .cloudAI] {
            XCTAssertTrue(
                ConsentCopy.info(for: category).isOptional, "\(category) should be optional")
        }
    }

    func testCopyMakesNoMedicalOrAdvertisingClaim() {
        for category in ConsentCategory.allCases {
            let text = ConsentCopy.info(for: category).purpose.lowercased()
            for banned in ["treat ", "cure", "advertis", "sell "] {
                XCTAssertFalse(text.contains(banned), "\(category) copy contains '\(banned)'")
            }
        }
        // The health category explicitly disclaims diagnosis rather than avoiding the word.
        XCTAssertTrue(
            ConsentCopy.info(for: .health).purpose.lowercased().contains("never a diagnosis"))
    }

    @MainActor
    func testViewModelSurfacesCurrentStatusForEveryCategory() async {
        let provider = StubConsentStatusProvider(statuses: [
            .alarm: .granted, .notifications: .granted, .motion: .denied, .location: .notDetermined,
            .health: .restricted, .calendar: .denied, .cloudAI: .denied,
        ])
        let model = ConsentCenterModel(provider: provider)
        await model.refresh()

        XCTAssertEqual(model.states.count, ConsentCategory.allCases.count)
        XCTAssertEqual(model.states.first { $0.info.category == .alarm }?.status, .granted)
        XCTAssertEqual(model.states.first { $0.info.category == .motion }?.status, .denied)
        XCTAssertEqual(model.states.first { $0.info.category == .cloudAI }?.status, .denied)
    }
}

/// A `ConsentStatusProviding` stub returning canned statuses.
private struct StubConsentStatusProvider: ConsentStatusProviding {
    let statuses: [ConsentCategory: ConsentStatus]

    func status(for category: ConsentCategory) async -> ConsentStatus {
        statuses[category] ?? .notDetermined
    }
}
