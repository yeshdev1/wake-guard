# Aesthetic consistency epoch (WG-209)

Consistency is enforced structurally by `AestheticConsistencyTests` (plus WG-202 typography): every screen
draws from the `DesignSystem`, so it can't drift.

## Consistent by construction

- **Spacing** — `DesignSystem.Spacing` (`xxs…xxl`); no raw numeric padding/spacing (except idiomatic
  `spacing: 0`).
- **Typography** — `DesignSystem.Typography` semantic styles that scale (no fixed point sizes, WG-202).
- **Color** — `DesignSystem.Colors` semantic tokens; no raw `Color.red`/`.green`/… in views (so dark mode +
  contrast stay right, WG-204).
- **Iconography** — SF Symbols throughout; status uses label + icon (WG-204).
- **Corner treatment** — `DesignSystem.Radius`; no raw `.cornerRadius(…)`.
- **Animation** — resolved through `MotionPreference`, Reduce-Motion-gated (WG-203).
- **Empty states** — sections render a short, honest message when there's nothing to show (e.g. readiness
  "not enough data").

## Visual hierarchy

Each screen has a clear hierarchy: a header (`Typography.screenTitle`/`sectionTitle` with
`.accessibilityAddTraits(.isHeader)`), primary content, secondary/support text in
`Colors.secondaryText`, and one prominent primary action.

## Before/after review

The before/after screenshot pass per screen is a manual review (attach to the PR). The structural pins here
prevent inconsistency regressions between reviews.
