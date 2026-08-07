# Release Checklist

> Run these **incrementally** at epoch boundaries per `docs/UAT_CHECKPOINTS.md`, not all at
> release — most items below belong to a specific checkpoint (CP-A…CP-I).

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
- [ ] Wake-challenge configuration on device: the "Wake challenge" section (None/Walk, duration/steps steppers, accessible-alternative picker) is legible and reflows at the largest Dynamic Type; VoiceOver announces each control's label + value; the phone-carry requirement is disclosed and the accessible alternative is clearly always available (#25, SCOPE §2.3); the duration/steps steppers can't be set to a degenerate challenge (the required cadence stays a plausible walk). The actual walk detection / pass-fail is verified separately (WG-072/075) (WG-045).
- [ ] Travel-policy configuration on device: the three options (follow local / keep home-zone / ask) are clear and reflow at the largest Dynamic Type; the anchor IANA zone is shown and VoiceOver reads it naturally (not spelling "New_York" or voicing "/"); the destination preview matches the chosen option; editing an alarm **while in a different time zone does not silently re-anchor** it (#16); no copy implies GPS/location tracking. The runtime travel detection is E06 (WG-046).
- [ ] Pre-alarm configuration on device: the "Smart pre-alarm" section (enable, lead-time window, action toggles) is legible + reflows at the largest Dynamic Type; VoiceOver reads the toggle/stepper (label + value) and each action toggle (+ hint); the disclosure clearly states that **no response leaves the alarm unchanged** (#7), notes an enabled-with-no-actions prompt is informational-only, and — for a critical alarm — shows that turning it off from the prompt needs confirmation (#6). The pre-alarm prompt runtime is E05 (WG-047).
- [ ] Alarm history on device: opening "History" from an alarm lists who/what/when for each change in plain language; a system/recovery/reconciliation entry is visibly distinct (icon + "System" tag, not color-alone) and reads "System action…" to VoiceOver (#50); the detail shows no raw hashes / ids / internal state (#41); a failed load reads distinctly from "no history yet"; rows + tags reflow at the largest Dynamic Type without truncating the outcome (WG-048).
- [ ] Deep links on device (**requires the `wakeguard://` URL scheme registered first** — WG-049 deferred that Info.plist step to the notification/AlarmKit work): opening `wakeguard://alarm/<id>` opens that alarm (no auto-change — #7); a deleted/unknown id and a `wakeguard://proposal/<id>` show a safe message, never a wrong or blank screen; a malformed link is a safe no-op; a link arriving while a create/edit sheet is open still lands the user on the target (the single-presenter consolidation) (WG-049).
- [ ] UI-test suite + screenshot baseline: `make test-ui` passes the six core flows (create / edit / delete / critical-delete-confirm / travel) on the release build's simulator; the attached key-state screenshots are reviewed and approved as the visual baseline; and the UI suite is wired into the fuller (non-fast) CI matrix (WG-050).
- [ ] Motion & Fitness permission on device (**UAT CP-C**): the request appears **in context** (setting up a walk challenge) *after* the specific purpose explanation, never at launch; declining — or a restricted/interrupted state — still lets the user turn off the alarm via the accessible tap / press-and-hold challenge (#21); the purpose copy names the specific use and disclaims location + saved workouts/health records (#41). Authorized-but-no-pedometer-hardware falls back to the alternative (WG-061).
- [ ] Historical pedometer on device (**UAT CP-C**): a bounded-window `CMPedometer` history query returns a validated step sample; a query whose data is missing/denied/no-hardware **throws** (never a silent empty that would read as "user was still") and the walk challenge falls back to the accessible alternative; the window can't read the future or an over-long range; and **no raw sample values or CoreMotion error text appear in any log** (#41) — a query failure surfaces only as the coarse "temporarily unavailable" state (WG-062).
- [ ] Live pedometer on device (**UAT CP-C**): a real walk produces a live step stream that reaches the walk challenge; **cancelling the challenge (or leaving the screen) stops `CMPedometer` updates** — confirm no pedometer updates keep running in the background (battery + privacy); duplicate/out-of-order/glitched deliveries don't corrupt progress and a mid-walk counter reset doesn't produce negative progress; a denied/no-hardware source **throws** (never a silent empty that reads as "didn't walk") → accessible alternative; and **no raw sample values or CoreMotion error text appear in any log** (#41) (WG-063).
- [ ] Motion activity on device (**UAT CP-C**): a real walk classifies as `walking` (single-flag) and reaches the challenge; a transition (e.g. walking+automotive) resolves to `unknown` rather than a false confident class; cancelling the challenge **stops `CMMotionActivityManager` updates** (no background leak); an **unsupported device** (no activity classifier) or a denied grant **throws** → accessible alternative (never an empty "no activity = stationary/asleep" stream); confidence is preserved and no raw activity state appears in logs (#41) (WG-064).
- [ ] Device-motion evidence on device (**UAT CP-C**): on real motion the evidence classifies a **still** phone as stationary, a genuine **pickup/carry** as pickup, and a **shake-on-nightstand** as irregular-shaking (never as pickup); a **slow deliberate tilt** may read as pickup (a known limitation — the walk challenge, not this evidence, is the wake gate); **calibrate the `DeviceMotionEvidenceAnalyzer` thresholds** on real still/pickup/shake motion (the CI defaults are cautious placeholders); confirm the evidence never claims a distance/displacement (WG-065).
- [ ] Altimeter evidence on device (**UAT CP-C**): a real stand-up / stairs corroborates movement (`significantChange`) while sitting still or normal weather/HVAC pressure drift does **not** (stays flat); a phone with **no barometer** has zero negative impact on any challenge (never a penalty); confirm a lone altitude `significantChange` alone does **not** pass a challenge (it only corroborates pedometer/accel movement — a fast door/HVAC/elevator transient looks the same to barometry); **calibrate the `AltitudeEvidenceAnalyzer` thresholds** on device (WG-066).
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
- [ ] Device-motion (CMDeviceMotion) battery cost measured at the challenge's sampling rate/window — the device-carried/pickup evidence runs on a bounded window, so continuous high-rate sampling must not be required (WG-065).
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
