import SwiftUI

// Reusable WakeGuard components (WG-040), built entirely from `DesignSystem` tokens — no
// raw layout literals. Each supports Dynamic Type (semantic fonts), dark mode / Increase
// Contrast (system-semantic colors), and VoiceOver (meaningful labels).

/// A pill showing an alarm's status by **icon + text**. The label and icon are drawn in a
/// high-contrast semantic color (WCAG AA legible, and the icon *shape* stays perceivable);
/// the status tint is a reinforcing background wash only, **never the sole signal**
/// (CLAUDE.md "do not rely on color alone" — protects color-blind, low-vision, and
/// Increase-Contrast users). VoiceOver reads the status label.
struct StatusBadge: View {
    let style: AlarmStatusStyle

    var body: some View {
        Label {
            Text(style.label)
        } icon: {
            Image(systemName: style.systemImage)
        }
        .font(DesignSystem.Typography.statusLabel)
        .foregroundStyle(DesignSystem.Colors.primaryText)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(style.tint.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(style.label)
        .accessibilityIdentifier("statusBadge")
    }
}

/// A grouped surface (card). Uses the semantic surface color and card radius; pads with a
/// token so content never sits against the edge.
struct SurfaceCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.lg)
            .background(
                DesignSystem.Colors.surface,
                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card))
    }
}

// Callers apply `.accessibilityIdentifier(_:)` (for UI tests) and, on destructive buttons,
// an `.accessibilityHint` describing the consequence — the styles restyle the label but
// cannot know the action's identity. Screens built on these (WG-041+) must set both.

/// The primary (accent) action style.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .filledControl(
                background: DesignSystem.Colors.accent, isPressed: configuration.isPressed)
    }
}

/// The **destructive** action style. It is distinct from the primary action by **more than
/// color** — a leading warning icon — so it holds up for color-blind and grayscale users
/// (CLAUDE.md "make destructive actions distinct"; "do not rely on color alone"). The icon
/// is generic (destructive intent, e.g. delete or cancel); a caller wanting a specific
/// glyph composes its own label. Confirming a critical change is the caller's job (#6);
/// this only provides the distinct affordance.
struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.label
        } icon: {
            Image(systemName: "xmark.octagon.fill")
        }
        .filledControl(
            background: DesignSystem.Colors.statusCritical, isPressed: configuration.isPressed)
    }
}

extension View {
    /// Shared filled-control chrome for the button styles — full-width, token padding,
    /// control radius, and a pressed dim. No fixed height, so it grows with Dynamic Type.
    fileprivate func filledControl(background: Color, isPressed: Bool) -> some View {
        self
            .font(DesignSystem.Typography.controlLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.md)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .foregroundStyle(DesignSystem.Colors.onFilled)
            .background(
                background, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
            )
            .opacity(isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: - Previews (dark mode + Dynamic Type — the WG-040 "previews pass" acceptance)

private struct ComponentGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            ForEach(AlarmStatusStyle.all, id: \.label) { StatusBadge(style: $0) }
            SurfaceCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Wake up").font(DesignSystem.Typography.cardTitle)
                    Text("Next: tomorrow 7:00 AM").font(DesignSystem.Typography.secondary)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }
            }
            Button("Save alarm") {}.buttonStyle(PrimaryButtonStyle())
            Button("Delete alarm") {}.buttonStyle(DestructiveButtonStyle())
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.screenBackground)
    }
}

#Preview("Components — light") {
    ComponentGallery()
}

#Preview("Components — dark") {
    ComponentGallery().preferredColorScheme(.dark)
}

#Preview("Components — accessibility text size") {
    ComponentGallery().environment(\.dynamicTypeSize, .accessibility3)
}
