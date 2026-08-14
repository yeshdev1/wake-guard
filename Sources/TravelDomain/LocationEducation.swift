import Foundation

/// User-facing education for the **optional** significant-location feature (WG-109). Explains the
/// **approximate purpose** (corroborating that a time-zone change looks like real travel — coarse, never
/// precise coordinates, #41), the **battery behavior** (low-power significant-location only, never
/// continuous GPS), and makes explicit that the app **works without location permission** (time-zone
/// travel detection and alarms run regardless, WG-100). Pure content so the copy is testable and the
/// SwiftUI view stays thin; localization is applied at the view layer.
struct LocationEducation: Sendable, Equatable, Hashable {
    /// What the approximate location is used for — coarse, never stored coordinates.
    let purpose: String
    /// The low-power battery behavior — significant-location only, never continuous GPS.
    let batteryBehavior: String
    /// The assurance that the feature is optional and the app works without granting location.
    let worksWithoutPermission: String

    static let standard = LocationEducation(
        purpose:
            "Alarm Agent uses your approximate location only to confirm that a time-zone change "
            + "looks like real travel. It never records where you are — only that your device moved.",
        batteryBehavior:
            "It uses low-power significant-location changes (based on cell and Wi-Fi), "
            + "never continuous GPS, so the battery impact is minimal.",
        worksWithoutPermission:
            "This is optional. Alarm Agent still detects time-zone changes and keeps "
            + "your alarms working even if you never grant location access.")
}
