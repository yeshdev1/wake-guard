# Accessibility manual audit checklist (WG-201/202/203/204/207)

Automated checks pin what code can prove (labels present, non-color status, Reduce-Motion honoured,
Dynamic-Type-safe layout, localized strings). This checklist is the **manual, on-device** audit that must
also pass before release.

## VoiceOver (WG-201)

- [ ] Create alarm, list, ringing, and challenge flows are completable **eyes-free**.
- [ ] Every control has a meaningful **label**; stateful controls expose a **value**; non-obvious controls
      have a **hint**.
- [ ] **Focus order** is logical top-to-bottom; the primary action is reachable without hunting.
- [ ] Alarm **status is announced** on change (uses `AlarmVoiceOver.statusAnnouncement`).
- [ ] Destructive actions **announce their consequence** before confirmation (uses
      `AlarmVoiceOver.consequence`); the ringing/challenge "still scheduled" state is announced.

## Dynamic Type (WG-202)

- [ ] At the **largest accessibility size**, no critical content is clipped or truncated.
- [ ] Controls remain reachable; no **horizontal scrolling** in core flows.
- [ ] Text uses `DesignSystem.Typography` (scales), never a fixed point size.

## Reduce Motion (WG-203)

- [ ] With **Reduce Motion** on, animations are removed or replaced with a cross-fade.
- [ ] Haptics are **supplementary** — progress is understandable without them.

## Contrast & non-color (WG-204)

- [ ] Every status has **text + icon** redundancy (never color alone).
- [ ] **Dark and light** modes both pass contrast.
- [ ] Critical warnings are distinguishable from ordinary status.

## Right-to-left (WG-207)

- [ ] Navigation, time rows, progress, and destructive actions **mirror** correctly.
- [ ] Directional icons (chevrons, arrows) are reviewed and mirror where appropriate.
