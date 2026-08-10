import XCTest

@testable import WakeGuard

/// Runs-on-a-phone step 5: the pre-alarm notification response runtime. Verifies the userInfo payload
/// round-trips and decodes **fail-closed**, and that a tapped action routes to the right effect — a
/// `turnOffToday` going through the processor (source `.notificationAction`), a **critical** turn-off
/// coming back `.needsConfirmation` (the alarm is unchanged until confirmed, #6), remind-later
/// **re-posting the advisory prompt** (never the alarm, #7/#8), and a corrupt payload / unknown action
/// changing nothing (#7).
final class PreAlarmNotificationResponderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 2_000_000)
    private let ids = DeterministicIDGenerator(seed: 5)

    private func makeContext(criticality: Criticality = .standard, remindersUsed: Int = 0)
        -> PreAlarmResponseContext
    {
        PreAlarmResponseContext(
            alarmID: AlarmID(ids.next()), occurrence: now.addingTimeInterval(3600),
            criticality: criticality, remindersUsed: remindersUsed)
    }

    private func makeResponder(
        _ processor: FakeAlarmCommandProcessor, _ scheduler: InMemoryPreAlarmNotificationScheduler
    ) -> PreAlarmNotificationResponder {
        PreAlarmNotificationResponder(processor: processor, notifications: scheduler)
    }

    private func effect(
        for actionIdentifier: String, context: PreAlarmResponseContext,
        processor: FakeAlarmCommandProcessor, scheduler: InMemoryPreAlarmNotificationScheduler
    ) async -> PreAlarmResponseEffect {
        await makeResponder(processor, scheduler).handle(
            actionIdentifier: actionIdentifier,
            userInfo: PreAlarmNotificationPayload.encode(context), now: now)
    }

    // MARK: - Payload

    func testPayloadRoundTrips() {
        let original = makeContext(criticality: .critical, remindersUsed: 2)
        XCTAssertEqual(
            PreAlarmNotificationPayload.decode(PreAlarmNotificationPayload.encode(original)),
            original)
    }

    func testPayloadDecodeFailsClosedOnCorruptFields() {
        XCTAssertNotNil(
            PreAlarmNotificationPayload.decode(PreAlarmNotificationPayload.encode(makeContext())))
        func corrupted(_ key: String, _ value: Any?) -> [AnyHashable: Any] {
            var info = PreAlarmNotificationPayload.encode(makeContext())
            info[key] = value
            return info
        }
        XCTAssertNil(PreAlarmNotificationPayload.decode(corrupted("wg.prealarm.alarmID", nil)))
        XCTAssertNil(
            PreAlarmNotificationPayload.decode(corrupted("wg.prealarm.alarmID", "not-a-uuid")))
        XCTAssertNil(
            PreAlarmNotificationPayload.decode(corrupted("wg.prealarm.criticality", "bogus")))
        XCTAssertNil(
            PreAlarmNotificationPayload.decode(corrupted("wg.prealarm.remindersUsed", "-1")))
        XCTAssertNil(PreAlarmNotificationPayload.decode(corrupted("wg.prealarm.occurrence", "inf")))
    }

    // MARK: - Routing

    func testKeepIsSubmittedAsAKeepOriginalNoOp() async {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let scheduler = InMemoryPreAlarmNotificationScheduler()
        let context = makeContext()
        let result = await effect(
            for: PreAlarmPromptAction.keep.identifier, context: context, processor: processor,
            scheduler: scheduler)
        XCTAssertEqual(
            result, .submitted(outcome: .applied, command: .keepOriginal(context.alarmID)))
        XCTAssertEqual(processor.seen, [.keepOriginal(context.alarmID)])
    }

    func testTurnOffTodaySubmitsCancelOccurrence() async {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let scheduler = InMemoryPreAlarmNotificationScheduler()
        let context = makeContext()
        let result = await effect(
            for: PreAlarmPromptAction.turnOffToday.identifier, context: context,
            processor: processor,
            scheduler: scheduler)
        XCTAssertEqual(
            result,
            .submitted(
                outcome: .applied,
                command: .cancelOccurrence(context.alarmID, fireTime: context.occurrence)))
        XCTAssertEqual(
            scheduler.cancels, [context.alarmID],
            "a turn-off that took effect reaps any pending re-prompt for the occurrence")
    }

    func testCriticalTurnOffComesBackNeedsConfirmationAndDoesNotApply() async {
        // #6: a critical turn-off from a notification is gated — the processor returns
        // `.needsConfirmation` and the alarm is unchanged until the app foregrounds to confirm.
        let processor = FakeAlarmCommandProcessor(
            outcome: .needsConfirmation(reason: "Confirm turning off a critical alarm."))
        let scheduler = InMemoryPreAlarmNotificationScheduler()
        let result = await effect(
            for: PreAlarmPromptAction.turnOffToday.identifier,
            context: makeContext(criticality: .critical), processor: processor, scheduler: scheduler
        )
        guard case .submitted(let outcome, _) = result, case .needsConfirmation = outcome else {
            return XCTFail(
                "a critical turn-off must come back .needsConfirmation (#6), got \(result)")
        }
        XCTAssertTrue(
            scheduler.cancels.isEmpty, "an unconfirmed critical turn-off leaves the prompt in place"
        )
    }

    func testRemindLaterRepostsThePromptNeverTheAlarm() async {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let scheduler = InMemoryPreAlarmNotificationScheduler()
        let context = makeContext(remindersUsed: 0)  // occurrence 1h out → a bounded remind fits
        let result = await effect(
            for: PreAlarmPromptAction.remindLater.identifier, context: context,
            processor: processor,
            scheduler: scheduler)
        XCTAssertEqual(result, .rescheduled(at: now.addingTimeInterval(300)))
        XCTAssertEqual(scheduler.posts.count, 1, "the advisory prompt is re-posted")
        XCTAssertEqual(
            scheduler.posts.first?.context.remindersUsed, 1, "the reminder count advances")
        XCTAssertTrue(processor.seen.isEmpty, "remind-later never touches the alarm (#7/#8)")
    }

    func testChangeTimeAsksToForegroundThePicker() async {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let scheduler = InMemoryPreAlarmNotificationScheduler()
        let context = makeContext()
        let result = await effect(
            for: PreAlarmPromptAction.changeTime.identifier, context: context, processor: processor,
            scheduler: scheduler)
        XCTAssertEqual(result, .presentChangeTimeUI(context.alarmID))
        XCTAssertTrue(processor.seen.isEmpty, "opening the picker changes nothing yet (#7)")
    }

    func testUnknownActionAndCorruptPayloadChangeNothing() async {
        let processor = FakeAlarmCommandProcessor(outcome: .applied)
        let scheduler = InMemoryPreAlarmNotificationScheduler()
        let unknown = await effect(
            for: "com.apple.UNNotificationDismissActionIdentifier", context: makeContext(),
            processor: processor, scheduler: scheduler)
        XCTAssertEqual(unknown, PreAlarmResponseEffect.none)
        // A corrupt payload never submits to a wrong/absent alarm.
        let corrupt = await makeResponder(processor, scheduler).handle(
            actionIdentifier: PreAlarmPromptAction.turnOffToday.identifier, userInfo: [:], now: now)
        XCTAssertEqual(corrupt, PreAlarmResponseEffect.none)
        XCTAssertTrue(processor.seen.isEmpty, "a corrupt payload is ignored, never mis-applied")
    }
}
