# Epoch 8 (WG-247): Accessibility review with assistive settings

A `ux-accessibility-reviewer` pass verified each a11y guarantee holds in source **and is regression-pinned**,
exercising VoiceOver, Dynamic Type, non-color status, Reduce Motion, contrast/dark mode, RTL, and the
walking-challenge accessible alternative.

**Verdict: the meaning-carrying a11y layer is strong and well-pinned; no assistive-setting user is blocked
on a shipping surface (no P0).** Two real gaps were at the *wiring/pin* seam — both fixed here.

## Fixed

- **F1 (P1) — destructive consequence not delivered in the shipping UI.** `AlarmVoiceOver.consequence(of:)`
  spoke the right outcome but was **dead code** — the reachable swipe-to-delete announced only "Delete", and
  the critical-change confirmation copy omitted the ring consequence. **Fixed:** the delete button now
  carries `.accessibilityHint(AlarmVoiceOver.consequence(of: .cancelAlarm))` ("Cancels this alarm. It will
  not ring."), and the critical `.needsConfirmation` reason now states "…it will no longer ring." Pins:
  `AlarmVoiceOverTests.testListViewDeleteActionWiresTheSpokenConsequence` (the helper is wired, not dead) and
  `DefaultAlarmPolicyEngineTests.testCancellingCriticalAlarmRequiresConfirmation` now asserts the reason
  contains "ring".
- **F2 (P1, latent) — Reduce Motion escape on the accessible hold bar, with a pin that couldn't catch it.**
  `AccessibleChallengeView`'s press-and-hold bar used `TimelineView(.animation(paused:))`, which grows the
  fill ~60fps **regardless of Reduce Motion**; `.animation(nil)` only removed the tween. The gate
  (`testAllAnimatedViewsAreReduceMotionGated`) is a per-file substring check, so it passed on an unrelated
  `reduceMotion` mention. **Fixed:** the timeline now throttles to coarse ~0.5s steps under Reduce Motion
  (`minimumInterval: reduceMotion ? 0.5 : nil`) — the bar still updates (functional feedback #22) but steps
  instead of continuously animating. New pin `testTimelineAnimationsAreReduceMotionThrottled` inspects the
  `TimelineView(.animation` construct itself. (The challenge screen is not hosted yet — see E14 — so this was
  latent, but the pin weakness was real and is now closed before the flow is wired.)

## Confirmed (enforcement → pin)

- **VoiceOver combined row.** `AlarmListViewModel.accessibilityLabel` builds one label leading with
  criticality, then label/status/next-ring; rows collapse children. Pins: `AlarmListViewModelTests`,
  `AlarmHistoryViewModelTests`.
- **Dynamic Type.** No `.system(size:)`, no truncating fixed heights; text-style fonts throughout; long
  screens scroll. Pin: `DynamicTypeLayoutTests`.
- **Non-color status.** Every `AlarmStatusStyle` carries label + SF Symbol + tint-as-reinforcement. Pins:
  `NonColorStatusTests`, `DesignSystemTests`.
- **Contrast / dark mode.** All colors system-semantic; status tints ride behind `Color.primary` icon+text.
  Pin: `AestheticConsistencyTests` (forbids raw colors).
- **RTL.** No absolute left/right; leading/trailing only. Pin: `RTLLayoutTests`.
- **Accessible alternative (#22).** Always offered until pass; sensor-unavailable keeps the alarm active and
  still offers it; assistive activation completes the hold so it is never a dead-end. Pins:
  `ChallengeViewModelTests`, `AccessibleChallengeViewModelTests`.

## Tracked (P2 / E14, not fixed here)

- `NonColorStatusTests` view-scan covers only ConsentCenter/AIAvailability; extend to `StatusBadge`/alarm-row
  when convenient (the value vocabulary is already pinned).
- `DestructiveButtonStyle` (icon-distinct destructive affordance) is orphaned — adopt or remove at E14.
- **E14 wiring:** the challenge / accessible-alternative screens and `ChallengeStopCoordinator` are not
  hosted (AlarmKit ring integration pending). When wired, add an end-to-end reachability UITest that reaches
  `challengeAccessibleAlternative` under a sensor-unavailable stub.
