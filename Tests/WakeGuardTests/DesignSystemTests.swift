import XCTest

@testable import WakeGuard

/// WG-040: the design-token and status-presentation contracts. SwiftUI rendering itself is
/// verified visually via the `#Preview`s (dark mode + Dynamic Type); these tests pin the
/// deterministic, meaning-carrying layer — the spacing scale and, critically, that each
/// alarm status conveys meaning by text and icon (never color alone).
final class DesignSystemTests: XCTestCase {

    func testSpacingScaleIsAscendingAndPositive() {
        let scale = DesignSystem.Spacing.scale
        XCTAssertEqual(scale, scale.sorted(), "the spacing scale is ascending")
        XCTAssertTrue(scale.allSatisfy { $0 > 0 }, "spacing values are positive")
        XCTAssertEqual(Set(scale).count, scale.count, "spacing steps are distinct")
    }

    func testRadiiArePositive() {
        XCTAssertGreaterThan(DesignSystem.Radius.control, 0)
        XCTAssertGreaterThan(DesignSystem.Radius.card, 0)
    }

    func testEveryStatusStyleCarriesTextAndIcon() {
        // "Do not rely on color alone": each status conveys meaning via a non-empty label
        // AND an SF Symbol, so the tint is only a reinforcing signal.
        for style in AlarmStatusStyle.all {
            XCTAssertFalse(style.label.isEmpty, "a status must have a text label")
            XCTAssertFalse(style.systemImage.isEmpty, "a status must have an icon")
        }
    }

    func testStatusStylesAreDistinctByLabelAndIcon() {
        let labels = AlarmStatusStyle.all.map(\.label)
        let icons = AlarmStatusStyle.all.map(\.systemImage)
        XCTAssertEqual(Set(labels).count, labels.count, "statuses are distinguishable by text")
        XCTAssertEqual(Set(icons).count, icons.count, "statuses are distinguishable by icon")
    }

    func testCriticalStatusIsDistinctFromScheduledBeyondColor() {
        // The safety-relevant pair must differ by more than color.
        XCTAssertNotEqual(AlarmStatusStyle.critical.label, AlarmStatusStyle.scheduled.label)
        XCTAssertNotEqual(
            AlarmStatusStyle.critical.systemImage, AlarmStatusStyle.scheduled.systemImage)
    }
}
