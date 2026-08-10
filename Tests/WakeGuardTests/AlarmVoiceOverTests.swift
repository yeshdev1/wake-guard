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
}
