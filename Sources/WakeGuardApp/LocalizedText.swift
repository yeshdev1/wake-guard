import Foundation

/// Safe, locale-aware count phrasing (WG-206). The number is formatted through `IntegerFormatStyle` (so
/// grouping/digits follow the locale — never a raw `String(count)`), and singular vs plural is chosen
/// explicitly. In production the plural rules live in the String Catalog; this helper is the code fallback
/// for non-SwiftUI contexts and keeps interpolation safe.
enum LocalizedText {
    static func alarmCount(_ count: Int, locale: Locale = .current) -> String {
        let number = count.formatted(.number.locale(locale))
        return count == 1 ? "\(number) alarm" : "\(number) alarms"
    }
}
