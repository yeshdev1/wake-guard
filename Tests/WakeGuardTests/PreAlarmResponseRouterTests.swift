import XCTest

@testable import WakeGuard

/// Pre-alarm composition: the notification-response router. Verifies a tapped prompt action maps to
/// the right runtime decision — keep → `keepOriginal` (WG-084), turn-off-today → `cancelOccurrence`
/// (WG-085), remind-later → a bounded re-prompt or stop (WG-087), change-time → present the in-app UI
/// (WG-086), and an unknown action is ignored. The router decides; it changes nothing itself.
final class PreAlarmResponseRouterTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 900)
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func context(remindersUsed: Int = 0, criticality: Criticality = .standard)
        -> PreAlarmResponseContext
    {
        PreAlarmResponseContext(
            alarmID: AlarmID(ids.next()), occurrence: now.addingTimeInterval(3600),
            criticality: criticality, remindersUsed: remindersUsed)
    }

    private func route(_ action: PreAlarmPromptAction, _ context: PreAlarmResponseContext)
        -> PreAlarmResponse
    {
        PreAlarmResponseRouter.route(
            actionIdentifier: action.identifier, context: context, now: now)
    }

    func testKeepRoutesToKeepOriginal() {
        let ctx = context()
        XCTAssertEqual(route(.keep, ctx), .submit(.keepOriginal(ctx.alarmID)))
    }

    func testTurnOffTodayRoutesToCancelOccurrence() {
        let ctx = context()
        XCTAssertEqual(
            route(.turnOffToday, ctx),
            .submit(.cancelOccurrence(ctx.alarmID, fireTime: ctx.occurrence)))
    }

    func testRemindLaterRoutesToABoundedReschedule() {
        XCTAssertEqual(
            route(.remindLater, context()), .reschedulePrompt(at: now.addingTimeInterval(300)))
    }

    func testRemindLaterExhaustedStopsReminding() {
        // The standard cap is 3 — a 4th remind is exhausted.
        XCTAssertEqual(route(.remindLater, context(remindersUsed: 3)), .stopReminding(.reachedCap))
    }

    func testChangeTimeRoutesToPresentTheInAppUI() {
        XCTAssertEqual(route(.changeTime, context()), .presentChangeTimeUI)
    }

    func testUnknownActionIsIgnored() {
        XCTAssertEqual(
            PreAlarmResponseRouter.route(
                actionIdentifier: "prealarm.action.bogus", context: context(), now: now),
            .ignored)
    }
}
