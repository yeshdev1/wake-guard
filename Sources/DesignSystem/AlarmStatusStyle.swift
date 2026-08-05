import SwiftUI

/// How an alarm's status is presented (WG-040): a **text label**, an **SF Symbol**, and a
/// tint. Meaning is carried by the label *and* the icon, so the tint is never the sole
/// signal (CLAUDE.md "do not rely on color alone"; supports color-blind users, Increase
/// Contrast, and VoiceOver, which reads `label`). Domain-independent — this is pure
/// presentation and maps from a domain status at the view layer, so `DesignSystem` keeps
/// no dependency on the alarm domain.
struct AlarmStatusStyle: Equatable, Sendable {
    /// User-facing status text (also the VoiceOver label).
    let label: String
    /// SF Symbol name conveying the status without color.
    let systemImage: String
    /// Tint — a secondary, reinforcing signal only.
    let tint: Color

    static let scheduled = AlarmStatusStyle(
        label: "Scheduled", systemImage: "alarm.fill", tint: DesignSystem.Colors.statusScheduled)
    static let critical = AlarmStatusStyle(
        label: "Critical", systemImage: "exclamationmark.triangle.fill",
        tint: DesignSystem.Colors.statusCritical)
    static let off = AlarmStatusStyle(
        label: "Off", systemImage: "alarm", tint: DesignSystem.Colors.statusOff)
    static let attention = AlarmStatusStyle(
        label: "Needs attention", systemImage: "exclamationmark.circle.fill",
        tint: DesignSystem.Colors.statusAttention)

    /// Every status the design system defines — used by previews and tests to prove each
    /// one carries a distinct label and icon (not just a color).
    static let all: [AlarmStatusStyle] = [.scheduled, .critical, .off, .attention]
}
