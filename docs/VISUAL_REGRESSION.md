# Device-size & orientation visual regression (WG-210)

Structural adaptivity is enforced **automatically** by `VisualRegressionTests` (source-scan pins: no fixed
widths, adaptive layouts, documented matrix). The pixel-level screenshot comparison is a **manual** pass on
the device/simulator matrix below — the project has **no** automated snapshot-diffing library or baseline
images yet (adding one is a future task; see "Screenshot-diff triage").

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

## Screenshot-diff triage (manual)

This pass is **manual**: a reviewer captures each core screen per device/orientation and compares it against
the checked-in baseline image set (maintained by hand). A diff is triaged as **intended** (update the
baseline in the same PR) or a **regression** (fix before merge); baselines are regenerated only with an
explicit, reviewed change.

Automated pixel diffing is **not** wired — the repo has no snapshot-testing library or baseline images (that
would be a third-party dependency requiring the privacy/maintenance assessment in CLAUDE.md). Until it is,
this manual triage plus the automated structural pins above is the guardrail. (WG-248 corrected this section:
the docs previously implied automated snapshot tests existed.)
