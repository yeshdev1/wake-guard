import XCTest

@testable import WakeGuard

/// WG-087: the remind-later action. Verifies a reminder is a **bounded** deferral that can never land
/// within a safe lead of (or past) the alarm, that **repeated prompts are capped** (per criticality),
/// that a **critical** alarm's schedule is never touched (the calc returns a prompt time only), and
/// that unsafe configs and non-finite clocks fail closed.
final class PreAlarmReminderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func fire(after seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    // MARK: - Bounded deferral

    func testFirstReminderIsABoundedInterval() {
        let plan = PreAlarmReminder.next(
            now: now, alarmFireTime: fire(after: 3600), remindersUsed: 0, criticality: .standard)
        XCTAssertEqual(plan, .remind(at: now.addingTimeInterval(300), remindersUsed: 1))
    }

    func testReminderNeverLandsWithinTheLeadOfTheAlarm() {
        let fireTime = fire(after: 3600)
        let plan = PreAlarmReminder.next(
            now: now, alarmFireTime: fireTime, remindersUsed: 0, criticality: .standard)
        let reminder = plan.reminderTime
        XCTAssertNotNil(reminder)
        // Strictly before the alarm, and at least the 120 s minimum lead before it.
        XCTAssertLessThanOrEqual(
            reminder ?? fireTime, fireTime.addingTimeInterval(-120),
            "the re-prompt keeps the minimum lead before the alarm")
        XCTAssertLessThan(reminder ?? fireTime, fireTime, "never at or after the alarm")
    }

    func testNoReminderWhenAFullDeferralWouldNotFitBeforeTheAlarm() {
        // 200 s to the alarm: a 300 s deferral + 120 s lead (420 s) cannot fit → no safe window.
        let plan = PreAlarmReminder.next(
            now: now, alarmFireTime: fire(after: 200), remindersUsed: 0, criticality: .standard)
        XCTAssertEqual(
            plan, .exhausted(.noSafeWindow), "a reminder cannot extend beyond safe bounds")
    }

    // MARK: - Repeated prompts are capped

    func testReminderCappedByCount() {
        let plan = PreAlarmReminder.next(
            now: now, alarmFireTime: fire(after: 3600), remindersUsed: 3, criticality: .standard)
        XCTAssertEqual(plan, .exhausted(.reachedCap), "the standard cap (3) is reached")
    }

    func testCriticalAlarmHasATighterCap() {
        // A critical alarm allows only one reminder (its schedule is untouched either way).
        let firstCritical = PreAlarmReminder.next(
            now: now, alarmFireTime: fire(after: 3600), remindersUsed: 0, criticality: .critical)
        XCTAssertNotNil(firstCritical.reminderTime, "the first critical reminder is allowed")
        let secondCritical = PreAlarmReminder.next(
            now: now, alarmFireTime: fire(after: 3600), remindersUsed: 1, criticality: .critical)
        XCTAssertEqual(
            secondCritical, .exhausted(.reachedCap), "a critical alarm caps at one reminder")
        // A standard alarm still reminds at the same used-count.
        let standard = PreAlarmReminder.next(
            now: now, alarmFireTime: fire(after: 3600), remindersUsed: 1, criticality: .standard)
        XCTAssertNotNil(standard.reminderTime)
    }

    func testNegativeRemindersUsedFailsClosed() {
        // A corrupted negative count must not reset the counter and grant a fresh reminder.
        let plan = PreAlarmReminder.next(
            now: now, alarmFireTime: fire(after: 3600), remindersUsed: -1, criticality: .standard)
        XCTAssertEqual(plan, .exhausted(.reachedCap))
    }

    func testWindowExhaustionIsDistinctFromCapWhenRemindersRemain() {
        // Reminders remain (used 0) but the window is too tight → noSafeWindow, not reachedCap.
        let plan = PreAlarmReminder.next(
            now: now, alarmFireTime: fire(after: 300), remindersUsed: 0, criticality: .standard)
        XCTAssertEqual(plan, .exhausted(.noSafeWindow))
    }

    // MARK: - Fail-closed + config safe bounds

    func testNonFiniteInputsFailClosed() {
        let nanNow = PreAlarmReminder.next(
            now: Date(timeIntervalSince1970: .nan), alarmFireTime: fire(after: 3600),
            remindersUsed: 0, criticality: .standard)
        XCTAssertEqual(nanNow, .exhausted(.noSafeWindow))
        let infFire = PreAlarmReminder.next(
            now: now, alarmFireTime: Date(timeIntervalSince1970: .infinity), remindersUsed: 0,
            criticality: .standard)
        XCTAssertEqual(infFire, .exhausted(.noSafeWindow))
    }

    func testConfigClampsAnUnsafeInterval() {
        // An interval below the floor clamps up to 60 s (never a near-instant re-prompt).
        let config = PreAlarmReminder.Config(
            interval: 1, standardMaxReminders: 3, criticalMaxReminders: 1, minLeadBeforeAlarm: 120)
        let plan = PreAlarmReminder.next(
            now: now, alarmFireTime: fire(after: 3600), remindersUsed: 0, criticality: .standard,
            config: config)
        XCTAssertEqual(plan, .remind(at: now.addingTimeInterval(60), remindersUsed: 1))
    }

    func testConfigCapsMaxRemindersAndCriticalNeverExceedsStandard() {
        // Standard clamps to the ceiling (5); critical can never exceed the (clamped) standard cap.
        let config = PreAlarmReminder.Config(
            interval: 300, standardMaxReminders: 100, criticalMaxReminders: 100,
            minLeadBeforeAlarm: 120)
        XCTAssertEqual(config.maxReminders(for: .standard), 5)
        XCTAssertEqual(config.maxReminders(for: .critical), 5)
        let tighter = PreAlarmReminder.Config(
            interval: 300, standardMaxReminders: 2, criticalMaxReminders: 10,
            minLeadBeforeAlarm: 120)
        XCTAssertEqual(
            tighter.maxReminders(for: .critical), 2, "critical cap can't exceed standard")
    }
}
