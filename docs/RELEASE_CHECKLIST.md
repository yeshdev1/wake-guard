# Release Checklist

## Product and safety

- [ ] Core alarm works without HealthKit, location, calendar, or AI.
- [ ] No AI path can call AlarmKit directly.
- [ ] No response to a pre-alarm prompt leaves the original alarm unchanged.
- [ ] Critical alarm cancellation/delay requires explicit confirmation.
- [ ] Critical alarm rings through silent mode, Focus, and Do Not Disturb on a real device (AlarmKit has no app-facing criticality knob — WG-026 assumes the system-alarm baseline; verify — WG-030).
- [ ] Ten-second challenge pass is validated on real devices.
- [ ] Shaking alone does not pass in the accepted test matrix.
- [ ] Accessible non-walking fallback works.
- [ ] Alarm state reconciles on launch/foreground: a **missing** system alarm is re-scheduled, an **extra** one is cancelled, and a **divergent** fire time is corrected, each producing a `systemReconciliation` audit entry (WG-029). Verify the real AlarmKit read-back reports **criticality** — else a critical alarm looks divergent every pass and is redundantly re-scheduled (WG-026/WG-029 seam). Confirm reconciliation never cancels a **currently ringing** alarm (future-only cancel, #24). Requires the launch/foreground trigger + processor composition (follow-on).
- [ ] Every mutation appears in audit history.
- [ ] Error UI states whether the alarm remains scheduled.

## Time

- [ ] DST spring-forward cases pass.
- [ ] DST fall-back cases pass.
- [ ] Half-hour/45-minute zones pass.
- [ ] International Date Line cases pass.
- [ ] Follow-local and fixed-zone semantics are documented and tested.
- [ ] Stale travel prompts are harmless.
- [ ] Manual clock/time-zone changes are tested.

## Lifecycle and reliability

- [ ] App terminated.
- [ ] Device restarted.
- [ ] Low Power Mode.
- [ ] Background App Refresh disabled.
- [ ] Notification permission revoked.
- [ ] Motion permission revoked mid-flow.
- [ ] Location/Health/Calendar denied and revoked.
- [ ] Storage/persistence failure.
- [ ] Duplicate/out-of-order callbacks.
- [ ] Async cancellation and uncertain external outcome.
- [ ] 100-cycle soak test.

## Privacy and security

- [ ] Privacy manifest.
- [ ] SDK inventory.
- [ ] Privacy Nutrition Label mapping.
- [ ] In-app privacy policy link.
- [ ] Explicit consent before third-party AI sharing.
- [ ] No raw sensitive logs.
- [ ] No health/motion/location/calendar advertising use.
- [ ] Export works.
- [ ] Deletion works.
- [ ] Secrets audit passes.
- [ ] Prompt injection corpus passes.

## Accessibility and visual quality

- [ ] VoiceOver.
- [ ] Dynamic Type at largest sizes.
- [ ] Reduce Motion.
- [ ] Increased contrast.
- [ ] Dark mode.
- [ ] 12/24-hour formats.
- [ ] RTL.
- [ ] Non-color status indicators.
- [ ] Design-system filled controls (primary / destructive) meet contrast on device against the shipped accent and system red at the smallest Dynamic Type size; the destructive action is distinguishable from the primary **without** color (WG-040).
- [ ] Alarm list on device: the next-ring time stays accurate after an alarm fires (foreground reload) and after a time-zone change; rows and the summary reflow (no truncation) at the largest Dynamic Type; a critical alarm is prominent and VoiceOver announces its criticality first; a failed/unavailable load never reads as "no alarms" (WG-041).
- [ ] Create-alarm on device: each MVP schedule type (weekly, one-time) creates and appears in the list; the next-occurrence preview updates live and honors 12/24-hour; an unsafe date (past one-time / no days / a minute that has lapsed) cannot be saved; a DST-boundary one-time (nonexistent / ambiguous wall-clock time) creates and resolves sensibly; the "won't ring yet" disclosure shows until the real AlarmKit adapter + authorization flow are wired — and once wired, a genuine schedule failure does **not** report "couldn't create" for an alarm that was saved (WG-042).
- [ ] Edit / enable-disable / delete on device: each routes through confirmation where required — a **critical** alarm's delete/disable/edit prompts, and cancelling (or no response) leaves it unchanged (#6); swipe-to-delete needs a deliberate two-step (no one-gesture full-swipe); the enable/disable toggle and the destructive actions are VoiceOver-legible (alarm name + on/off consequence, not color-alone) and reflow at the largest Dynamic Type; a failed action states whether the alarm is still scheduled (#41 coarse); an edit preserves criticality and the alarm remains saved-but-not-ringing until the AlarmKit adapter lands (WG-043).
- [ ] Critical alarm configuration on device: the "Critical alarm" toggle sets/clears criticality and its plain-language explanation is legible and reflows at the largest Dynamic Type; making an alarm critical needs no confirmation but turning it off / weakening it does (#6); no model/AI path can set criticality (#31); the "designed to ring through silent / Focus / Do Not Disturb" behavior is device-verified via SMK-04 once AlarmKit scheduling is wired — the interim adapter doesn't ring yet, so the copy must not present-tense over-promise (WG-044).
- [ ] Touch targets.
- [ ] Sleep-inertia usability.
- [ ] Approved screenshot baseline.
- [ ] All key empty/loading/error/success states.

## Performance and battery

- [ ] Cold-launch budget.
- [ ] Reconciliation budget.
- [ ] Challenge start/pass latency.
- [ ] Overnight idle battery.
- [ ] Location/travel battery.
- [ ] No memory growth in soak test.
- [ ] AI latency has deterministic fallback.

## Store submission

- [ ] Latest stable toolchain accepted by App Store.
- [ ] Archive contains no debug tools.
- [ ] App Review notes explain AlarmKit, challenge, optional permissions, and AI safety.
- [ ] Metadata contains no diagnostic claims.
- [ ] Screenshots match shipping build.
- [ ] Support URL and privacy URL work.
- [ ] Demo steps work for reviewer.
- [ ] TestFlight critical matrix passed on exact build.
- [ ] Rollback and smart-feature kill-switch plan exists.
