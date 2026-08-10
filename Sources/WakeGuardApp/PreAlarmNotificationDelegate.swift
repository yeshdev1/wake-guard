import UserNotifications

/// The app's `UNUserNotificationCenterDelegate` (runs-on-a-phone step 5): routes a tapped pre-alarm
/// prompt action through the `PreAlarmNotificationResponder`. A **keep** / **standard turn-off** /
/// **remind-later** is executed directly (the turn-off through `AlarmCommandProcessor`, source
/// `.notificationAction`); a **critical** turn-off comes back `.needsConfirmation` and the alarm is left
/// unchanged (#6); **change-time** needs the in-app picker. Surfacing the confirmation / picker on
/// foreground is a documented follow-up — the alarm is never wrongly changed in the meantime (#6/#7).
///
/// `@unchecked Sendable` (deliberate, not a silenced warning): the delegate is installed on a nonisolated
/// framework object and its callbacks run off the main actor, but every stored property is an immutable
/// `Sendable` value (a value-type responder + a `@Sendable` clock), so it is data-race-free by
/// construction — `@unchecked` only because an `NSObject` subclass can't be checked automatically.
final class PreAlarmNotificationDelegate: NSObject, UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    private let responder: PreAlarmNotificationResponder
    private let now: @Sendable () -> Date

    init(responder: PreAlarmNotificationResponder, now: @escaping @Sendable () -> Date) {
        self.responder = responder
        self.now = now
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        // Extract the Sendable routing inputs here (nonisolated) so the non-Sendable UN* types never
        // cross into the responder.
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        _ = await responder.handle(
            actionIdentifier: actionIdentifier, userInfo: userInfo, now: now())
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show the prompt even in the foreground so the user still sees it.
        [.banner, .sound]
    }
}
