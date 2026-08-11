import Foundation
import XCTest

@testable import WakeGuard

/// WG-201: VoiceOver announcements. Verifies **alarm status is announced** (every status has a spoken
/// label; the announcement includes the next ring), and that **destructive consequences are announced** —
/// every destructive action speaks its outcome, and alarm-affecting ones say whether the alarm will still
/// ring. Backs the eyes-free core flows (with the manual audit in `docs/ACCESSIBILITY_CHECKLIST.md`).
final class AlarmVoiceOverTests: XCTestCase {

    func testEveryAlarmStatusHasASpokenLabel() {
        for style in AlarmStatusStyle.all {
            XCTAssertFalse(style.label.isEmpty, "status has no VoiceOver label")
        }
    }

    func testStatusAnnouncementIncludesTheNextRingTime() {
        let announcement = AlarmVoiceOver.statusAnnouncement(.scheduled, nextRing: "7:00 AM")
        XCTAssertTrue(announcement.contains("Scheduled"))
        XCTAssertTrue(announcement.contains("7:00 AM"))
    }

    func testStatusAnnouncementWithoutNextRingIsJustTheLabel() {
        XCTAssertEqual(AlarmVoiceOver.statusAnnouncement(.off, nextRing: nil), "Off")
    }

    func testEveryDestructiveActionAnnouncesItsConsequence() {
        for action in DestructiveAction.allCases {
            let consequence = AlarmVoiceOver.consequence(of: action).lowercased()
            XCTAssertFalse(consequence.isEmpty, "\(action) has no spoken consequence")
        }
    }

    func testAlarmAffectingActionsStateTheRingConsequence() {
        for action in [
            DestructiveAction.cancelAlarm, .deleteAllData, .disableCriticalAlarm,
        ] {
            XCTAssertTrue(
                AlarmVoiceOver.consequence(of: action).lowercased().contains("ring"),
                "\(action) must announce whether the alarm will ring")
        }
        // Optional-data deletion reassures the user their alarms are unaffected.
        XCTAssertTrue(
            AlarmVoiceOver.consequence(of: .deleteOptionalData).lowercased().contains("unaffected"))
    }

    func testListViewDeleteActionWiresTheSpokenConsequence() throws {
        // The consequence helper must be *used* on the reachable delete affordance, not dead code: a
        // VoiceOver user swiping to delete hears the ring consequence as the button's hint (WG-247).
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let listView = try String(
            contentsOf: root.appendingPathComponent("Sources/WakeGuardApp/AlarmListView.swift"),
            encoding: .utf8)
        XCTAssertTrue(
            listView.contains("accessibilityHint(AlarmVoiceOver.consequence"),
            "the delete action must speak its consequence as an accessibility hint")
    }
}
