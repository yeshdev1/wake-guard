# Epoch 9 (WG-248): Aesthetic & interaction polish

A `ux-accessibility-reviewer` pass verified design-token consistency, sleep-inertia appropriateness, status
prominence, destructive/critical distinction, interaction consistency, and visual-regression coverage — and
probed each pin for effectiveness.

**Verdict: the design system is consistent and mostly pinned; the reachable home flow is calm, legible, and
status-forward.** Three real gaps fixed; the rest are latent (unhosted screens → E14) or documented honestly.

## Reachability reality (frames the findings)

The only screens composed from the app entry point are `AlarmListView` (+ `CreateAlarmView` sheet,
`AlarmHistoryView`, the permission/reconciling/scheduling banners). Onboarding, the wake/challenge screens,
conversational creation, readiness, tomorrow plan, consent center, data export/deletion, and diagnostics are
**not** navigable yet — an E14 wiring gap, not an aesthetic defect. Their components are well-built; they
just can't be experienced (or regress) through the composed app today.

## Fixed

- **Primary-CTA style consistency (P1).** Two treatments were used for the same role: the custom
  `PrimaryButtonStyle` token (full-width filled) and SwiftUI's `.buttonStyle(.borderedProminent)`. The four
  **full-width** primary CTAs that used `.borderedProminent` (Conversational ×2, Onboarding, DataExport,
  Diagnostics) now use `PrimaryButtonStyle`, matching the challenge/empty-state CTAs. `AlarmPermissionBanner`
  keeps `.borderedProminent` + `.controlSize(.small)` — a *deliberate compact inline* affordance (a
  documented hit-target choice), a different role, not an inconsistency. Pin:
  `AestheticConsistencyTests.testPrimaryCTAsUseTheSharedButtonStyleNotBorderedProminent` (a view using
  `.borderedProminent` must pair it with `.controlSize(.small)`, else use `PrimaryButtonStyle`).
- **Raw text-style fonts (P2, reachable).** `CompositionErrorView` (the reachable composition-failure screen)
  and an `AlarmListComponents` icon used raw `.font(.largeTitle)`/`.font(.title.bold())`/`.font(.footnote)`
  instead of `DesignSystem.Typography`. Re-pointed to `Typography.screenTitle`/`sectionTitle`/`caption` (they
  already scaled with Dynamic Type — this is consistency, not an a11y fix). Locked by adding `.font(.` to the
  `AestheticConsistencyTests` forbidden-token scan (0 raw text-style fonts remain in the app layer).
- **Visual-regression docs overstated automation (P1, honesty).** `VISUAL_REGRESSION.md` implied automated
  snapshot tests render each screen and diff a checked-in baseline. Reality: there is **no** snapshot library
  or baseline images — `VisualRegressionTests` pins *structure* (no fixed widths, adaptive layout) and the
  *documented* matrix; the pixel diff is a **manual** device-matrix pass. Corrected the doc to say so (a real
  snapshot library would be a third-party dependency needing the CLAUDE.md privacy/maintenance assessment).

## Confirmed

- **Token consistency (spacing/radius/color).** No raw `Color.<name>`/numeric padding/cornerRadius/non-zero
  spacing in shipping views. Pin: `AestheticConsistencyTests`.
- **Status prominence.** The home screen leads with a dedicated "Next alarm" section (next-ring text +
  `StatusBadge`) above the list; "still scheduled" / "saved but won't ring yet" / permission-loss states are
  stated explicitly in text, not color alone.
- **Destructive/critical distinction.** Swipe-delete is a two-step trash `role: .destructive`; critical/edit
  changes route through a confirm alert; critical status shows label+icon. (Cross-checked with WG-247.)
- **Sleep-inertia structure.** Wake screens use large titles, ≤3 controls, generous touch bounds. Pin:
  `SleepInertiaTests`.

## Tracked (P2 / E14, not fixed here)

- **Orphaned `DestructiveButtonStyle` / `SurfaceCard`.** Defined, distinct-beyond-color, but unused — adopt
  for destructive buttons or remove at E14 (reachable destructive actions currently rely on `role:
  .destructive`, which the confirmations + trash icon keep non-color-safe).
- **Wake-screen copy-length pin is effectively unenforced** — the wake screens render view-model strings, but
  `testWakeScreenCopyIsShort` only inspects `Text("literal")`. Add `count <= maxWakeCopyCharacters`
  assertions in the wake view-model tests when those screens are wired (E14).
- **No rendered-structure snapshot pin** — covered by the manual pass + structural scans until a snapshot
  library is assessed/added.
