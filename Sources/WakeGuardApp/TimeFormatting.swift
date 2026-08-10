import Foundation

/// Formats a stored `TimeOfDay` for display (WG-205). Formatting **follows the user's locale** and 12/24-
/// hour setting (via `Date.FormatStyle`), while the stored value stays **locale-independent** — the domain
/// keeps `TimeOfDay` (numeric hour/minute), and only display goes through here. Used where SwiftUI's
/// `Text(_:format:)` isn't available (VoiceOver announcements, notifications).
enum TimeFormatting {
    static func string(
        for time: TimeOfDay, locale: Locale = .current, calendar: Calendar = .current
    ) -> String {
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        guard let date = calendar.date(from: components) else {
            return String(format: "%02d:%02d", time.hour, time.minute)
        }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }
}
