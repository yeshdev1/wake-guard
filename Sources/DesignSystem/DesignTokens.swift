import SwiftUI

/// Design tokens (WG-040): the single source of semantic typography, spacing, radius, and
/// color for every WakeGuard screen. Components and screens reference these, never raw
/// literals, so there are **no hard-coded layout assumptions** and a change here reflows
/// the whole app. Typography is built on Dynamic Type text styles (scales automatically),
/// and colors are system-semantic (adapt to dark mode and Increase Contrast).
extension DesignSystem {

    /// A single spacing scale. Use these for padding/stacks instead of raw numbers.
    enum Spacing {
        /// 2
        static let xxs: CGFloat = 2
        /// 4
        static let xs: CGFloat = 4
        /// 8
        static let sm: CGFloat = 8
        /// 12
        static let md: CGFloat = 12
        /// 16
        static let lg: CGFloat = 16
        /// 24
        static let xl: CGFloat = 24
        /// 32
        static let xxl: CGFloat = 32

        /// Ascending order — used by tests to pin the scale and by any code that iterates it.
        static let scale: [CGFloat] = [xxs, xs, sm, md, lg, xl, xxl]
    }

    /// Corner radii for surfaces and controls.
    enum Radius {
        static let control: CGFloat = 8
        static let card: CGFloat = 12
    }

    /// Semantic fonts on Dynamic Type text styles — every one scales with the user's text
    /// size (never a fixed point size).
    enum Typography {
        static let screenTitle = Font.largeTitle.bold()
        static let sectionTitle = Font.title3.weight(.semibold)
        static let cardTitle = Font.headline
        static let body = Font.body
        static let secondary = Font.subheadline
        static let caption = Font.footnote
        static let statusLabel = Font.footnote.weight(.semibold)
        /// Filled-control label — **bold** so white-on-accent/red meets the WCAG large-text
        /// (3:1) contrast bar even at the smallest Dynamic Type size (see `Colors.onFilled`).
        static let controlLabel = Font.body.weight(.bold)
    }

    /// Semantic colors. Surfaces and text are system-semantic so they adapt to dark mode
    /// and Increase Contrast automatically. Status colors are only ever used **alongside a
    /// text label and an SF Symbol** (see `AlarmStatusStyle`), never as the sole signal —
    /// CLAUDE.md "do not rely on color alone."
    enum Colors {
        static let screenBackground = Color(.systemBackground)
        static let surface = Color(.secondarySystemBackground)
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary

        static let statusScheduled = Color.green
        static let statusCritical = Color.red
        static let statusOff = Color.secondary
        static let statusAttention = Color.orange

        /// The accent used by the primary action.
        static let accent = Color.accentColor
        /// Foreground on a filled (accent / destructive) control. White-on-accent/red clears
        /// WCAG only via the **bold, large-text** exception (`Typography.controlLabel`); if the
        /// shipped `accent` is ever lightened, re-verify on device (RELEASE_CHECKLIST).
        static let onFilled = Color.white
    }
}
