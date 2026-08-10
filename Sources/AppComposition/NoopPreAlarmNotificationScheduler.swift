import Foundation

/// A no-op `PreAlarmNotificationScheduling` for the in-memory (test/preview) graph: previews and unit
/// tests must never touch `UserNotifications`, so nothing is registered, posted, or cancelled. The
/// production graph composes `SystemPreAlarmNotificationScheduler`.
struct NoopPreAlarmNotificationScheduler: PreAlarmNotificationScheduling {
    func registerPromptCategory() async {}
    func postPrompt(_ context: PreAlarmResponseContext, at date: Date) async {}
    func cancelPrompt(alarmID: AlarmID, occurrence: Date) async {}
}
