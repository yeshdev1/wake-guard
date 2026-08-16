import Foundation
import UserNotifications

/// The real `TravelUpdateNotifying` (WG-304): posts an immediate local notification telling the user their
/// alarms were recomputed for a new time zone. Reuses the notification permission already requested for the
/// pre-alarm prompt (alert + sound) — no separate ask; a denial simply means no banner (the change is still
/// in History). One of the few places `UserNotifications` is touched. It never touches an alarm (#9).
struct SystemTravelUpdateNotifier: TravelUpdateNotifying {

    /// A stable identifier so a rapid second zone change replaces the previous banner rather than stacking.
    private static let identifier = "travelUpdate"

    func notifyAlarmsUpdated(forNewZone zone: IANATimeZone) async {
        let content = UNMutableNotificationContent()
        content.title = "Time zone changed"
        content.body =
            "You’ve entered a new time zone (\(Self.readableName(zone))). Your alarms have been "
            + "updated to keep the times you set — tap to review."
        // Deliver now: `nil` trigger fires immediately. A missed banner is safe — the alarms are already
        // rescheduled and the change is recorded in History (#9).
        let request = UNNotificationRequest(
            identifier: Self.identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// A user-readable zone name — the city component of the IANA identifier ("America/New_York" → "New
    /// York"), falling back to the full identifier. Contains no sensitive data (a public zone name, #41).
    private static func readableName(_ zone: IANATimeZone) -> String {
        let identifier = zone.identifier
        guard let city = identifier.split(separator: "/").last else { return identifier }
        return city.replacingOccurrences(of: "_", with: " ")
    }
}
