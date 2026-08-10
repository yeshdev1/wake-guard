# Device-size & orientation visual regression (WG-210)

Structural adaptivity is enforced by `VisualRegressionTests`; the pixel-level screenshot regression runs on
the device/simulator matrix below.

## Device matrix

| Class | Device | Why |
|---|---|---|
| Minimum | iPhone SE (3rd gen) — 4.7", 375 pt | Smallest supported width; catches clipping/overflow. |
| Small modern | iPhone 15/16 (mini-class widths) | Common compact size. |
| Current | iPhone 16 Pro Max — largest phone | Largest phone canvas; safe-area/notch. |
| Tablet | iPad (portrait + landscape) | `TARGETED_DEVICE_FAMILY = "1,2"` includes iPad. |

## Adaptivity (pinned)

- **No fixed widths.** Views use adaptive layout (`VStack`/`ScrollView`, `maxWidth`), never a hardcoded
  `.frame(width: <points>)` — so content reflows on the smallest device without horizontal clipping (a scan
  pins this; combines with WG-202's "no horizontal scrolling").
- Spacing/typography scale from the `DesignSystem` (WG-202/209).

## Landscape

Landscape is **intentional**: the core flows are vertical stacks inside a `ScrollView`, so they reflow and
scroll in landscape without clipping. On iPad, the larger canvas is used with the same components. There is
no landscape-only or portrait-locked screen; the ringing/challenge screen is legible in both.

## Screenshot-diff triage

Snapshot tests render each core screen per device/orientation and diff against a checked-in baseline. A diff
is triaged as: **intended** (update the baseline in the same PR), or a **regression** (fix before merge).
Baselines are regenerated only with an explicit, reviewed change.
