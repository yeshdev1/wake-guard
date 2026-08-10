import Foundation
import UserNotifications

/// The real `PreAlarmNotificationScheduling` (runs-on-a-phone step 5): besides the category factory,
/// the only place that touches `UserNotifications`. Registers the prompt category, posts the advisory
/// prompt as a **calendar-triggered** local notification carrying the routing payload, and cancels a
/// pending prompt. It never touches an alarm — the prompt is the advisory surface only (#7/#8). Not
/// unit-tested (system types need a device); the routing + payload logic it drives is tested in
/// `AlarmApplication`.
struct SystemPreAlarmNotificationScheduler: PreAlarmNotificationScheduling {

    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async {
        // A denial is not an error here — it just means no advisory prompt appears; the alarm (a
        // separate AlarmKit surface) still rings (#7/#8).
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func registerPromptCategory() async {
        center.setNotificationCategories([
            PreAlarmNotificationCategoryFactory.category(for: .forCategoryRegistration)
        ])
    }

    func postPrompt(_ context: PreAlarmResponseContext, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = localized(PreAlarmPromptContent.titleKey)
        content.body = localized(PreAlarmPromptContent.warningKey)
        content.categoryIdentifier = PreAlarmPromptContent.categoryIdentifier
        content.userInfo = PreAlarmNotificationPayload.encode(context)
        // A calendar trigger fires at the absolute instant (no now-read, no drift if the app is
        // suspended between scheduling and firing). A past date simply never fires — the alarm still
        // rings, so a missed prompt is safe (#7/#8).
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        let request = UNNotificationRequest(
            identifier: identifier(context.alarmID, context.occurrence), content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try? await center.add(request)
    }

    func cancelPrompt(alarmID: AlarmID, occurrence: Date) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(alarmID, occurrence)])
    }

    /// A stable per-(alarm, occurrence) identifier so a re-post replaces the same pending prompt and a
    /// cancel targets it. Whole-second `Double` (never `Int(...)`, which would trap on `.distantFuture`).
    private func identifier(_ alarmID: AlarmID, _ occurrence: Date) -> String {
        let seconds = occurrence.timeIntervalSince1970
        let whole = seconds.isFinite ? seconds.rounded(.towardZero) : 0
        return "prealarm.\(alarmID.rawValue.uuidString).\(whole)"
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(
            key, value: PreAlarmPromptStrings.developmentFallback(for: key),
            comment: "Pre-alarm prompt")
    }
}
