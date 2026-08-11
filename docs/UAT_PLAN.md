# WakeGuard — User Acceptance Test (UAT) Plan

Fine-grained, evidence-driven UAT for the wired build. Every test states the **exact data to collect** so a
result is defensible, not a "looks fine." Safety-critical items require a **physical device** (marked
`[DEVICE]`); the rest run on the **simulator** (marked `[SIM]`).

Build under test: record the **build number** (`make release-notes` → `build:`), the **device/OS**, and the
**date/time + time zone** at the top of every run.

---

## 0. Evidence sources (use these, not just screenshots)

WakeGuard produces its own machine-checkable evidence — collect these as artifacts:

1. **Data export** — Privacy & data → *Export your data* → Prepare export → Share → save the JSON. It
   contains `alarms`, `audit`, and `settings` categories. Use it to verify schedules, criticality, and the
   **audit trail** (every mutation: actor, reason, old/new hash, timestamp, outcome).
2. **Diagnostics report** — Privacy & data → *Diagnostics* → Export diagnostics → save the text. It contains
   per-permission status, the **last reconciliation summary** (scheduled/cancelled/failed/uncertain/stale),
   and the **last safe schedule sync** time. It is **redacted** — verify it contains no raw sleep/location/
   calendar/journal/prompt text.
3. **Screenshots** — one per numbered step where UI state matters. Name `TESTID-stepN.png`.
4. `[DEVICE]` **Console/Instruments** — for ring latency and battery, use the Energy Log / a stopwatch.

**Global pass rule:** any crash, any silent data loss, any case where the app implies an alarm is safe when
it is not, or any raw sensitive value found in an export/diagnostics = **FAIL**, regardless of the step.

---

## 1. Core alarm lifecycle `[SIM]`

### UAT-A1 — Create an alarm (manual)
- **Pre:** fresh launch; past onboarding.
- **Steps:** (1) + → *Add manually*. (2) Set 07:00, weekdays Mon–Fri, label "Work". (3) Save.
- **Collect:** row's next-ring text; **export** → the `alarms` entry (assert `schedule.weekly.days` = Mon–Fri,
  `time` = 07:00, `timeZone` = your IANA zone, `criticality` = standard); the `audit` entry (actor `user`,
  outcome `succeeded`, a non-null `newStateHash`).
- **Expected:** alarm appears under "All alarms" and in "Next alarm"; export + audit match the inputs.

### UAT-A2 — Edit, enable/disable, delete
- **Steps:** (1) Tap the row → change time to 06:30 → Save. (2) Toggle the switch off, then on. (3) Swipe →
  Delete.
- **Collect:** after each action, **export** and diff: edit → `revision` incremented + new time; disable →
  status "Off" + an audit event with reason "Alarm disabled."; delete → the alarm absent from `alarms` and a
  delete audit event present (the audit is **append-only** — the delete is recorded, not erased).
- **Expected:** each state change is reflected in the list **and** produces exactly one audit event.

### UAT-A3 — Empty / error states
- **Steps:** delete all alarms.
- **Collect:** screenshot the empty state ("No alarms yet").
- **Expected:** an explicit empty message, never a blank screen.

---

## 2. Safety invariants `[SIM]` (core — do not skip)

### UAT-B1 — Critical-alarm change is confirmation-gated (#6)
- **Pre:** create an alarm and set it **Critical** (Add manually → Critical toggle).
- **Steps:** (1) Try to disable it. (2) Read the confirmation dialog. (3) Cancel. (4) Repeat and Confirm.
- **Collect:** the **exact confirmation text** — it **must contain the word "ring"** (states the consequence);
  screenshot it. After Cancel: export shows the alarm still enabled + critical (no change). After Confirm:
  the audit event with the confirmed change.
- **Expected:** no critical change happens without an explicit confirm; the copy names the ring consequence.
- **FAIL if:** the alarm disables without a confirm, or the dialog omits the ring consequence.

### UAT-B2 — Reconciliation never silently drops an alarm (#10)
- **Steps:** (1) Create an enabled alarm. (2) Background the app; foreground it. (3) Open Diagnostics.
- **Collect:** the diagnostics **Reconciliation** line (scheduled/cancelled/failed/uncertain/stale) and
  **Last safe schedule sync** timestamp; export → the alarm is still present + enabled.
- **Expected:** the alarm survives background/foreground; the sync time updates; `failed` = 0.

### UAT-B3 — Kill / relaunch persistence
- **Steps:** (1) Create 3 alarms (1 critical). (2) Force-kill the app. (3) Relaunch.
- **Collect:** export **before** kill and **after** relaunch — assert identical `alarms` (ids, schedules,
  criticality). Diagnostics after relaunch: a fresh reconcile with `failed` = 0.
- **Expected:** all alarms + criticality survive a cold relaunch (persist-first, #10).

---

## 3. Alarm ringing + walk challenge `[DEVICE]`

### UAT-C1 — A critical alarm rings through silent mode / Focus (WG-030)
- **Pre:** real device; grant AlarmKit + notifications; set the device to silent + enable a Focus.
- **Steps:** schedule a critical alarm ~2 min out; lock the phone; wait.
- **Collect:** **scheduled time vs actual ring time** (stopwatch) — record the delta; whether it rang under
  silent + Focus (yes/no); whether it woke the screen. Repeat 3×; record each delta.
- **Expected:** rings within a few seconds of the scheduled instant, through silent + Focus, every time.
- **FAIL if:** it does not ring, or rings only when the device is unlocked/unmuted.

### UAT-C2 — Walk challenge: real gait passes, shake does not (#19/#20) — via "Test challenge"
- **Pre:** an alarm with a walk challenge; grant Motion & Fitness.
- **Steps:** (1) Swipe the alarm row → *Test challenge*. (2) **Walk** the required steps → observe pass.
  (3) Re-open; **shake** the phone in place (do not walk) for the same count.
- **Collect:** required step count (from the challenge screen); walked case → passed = yes + the export's
  `audit` shows exactly **one** `markChallengePassed`; shaken case → passed = **no** + **no** new
  `markChallengePassed` audit event. Record step counts and elapsed time for both.
- **Expected:** a genuine walk passes and stops the ring exactly once; a shake never passes and never stops.
- **FAIL if:** a shake passes, or a pass emits more than one stop.

### UAT-C3 — Accessible alternative is never a dead end (#21/#22)
- **Steps:** in *Test challenge* → "Can't walk? Use another way" → complete the tap/hold.
- **Collect:** the accessible completion → exactly one stop in the audit; verify the walk path is not required.
- **Expected:** the fallback completes and stops the ring; a user who can't walk is never trapped.

---

## 4. Privacy & data controls `[SIM]`

### UAT-D1 — Export contains only the promised, non-sensitive data (#41/#42)
- **Steps:** Privacy & data → Export → Prepare → Share → save JSON.
- **Collect:** the JSON. Assert categories = {alarms, audit, settings}; **search it** for any raw value that
  must never appear — a location coordinate, a calendar title, sleep numbers, journal text, an LLM prompt.
- **Expected:** export round-trips the alarm/audit/settings data; **zero** raw sensitive values present.
- **FAIL if:** any raw sensitive value appears.

### UAT-D2 — Delete: optional vs full reset (#9/#42)
- **Steps:** (1) Delete → select an **optional** category → Delete. (2) Full reset: request → **read the
  confirmation** (names the alarm consequence) → Cancel → confirm again → Confirm.
- **Collect:** after the optional delete → export shows **alarms unchanged** (optional deletion never touches
  alarms). After full reset → export shows **all** categories empty; the alarm list is empty; if you had a
  cloud token, it is revoked. Screenshot the full-reset confirmation copy.
- **Expected:** optional deletion spares alarms; full reset (only after explicit confirm) clears everything
  and cancels scheduled alarms.
- **FAIL if:** optional deletion removes an alarm, or a full reset proceeds without the confirm.

### UAT-D3 — Consent center reflects real permission status
- **Steps:** Privacy & data → Permissions & privacy; then change one permission in iOS Settings; return.
- **Collect:** each category's status before/after; screenshot. Compare to iOS Settings ground truth.
- **Expected:** every category (alarm, notifications, motion, location, health, calendar, cloud AI) shows a
  status; it matches iOS Settings after a change; toggling nothing here changes whether an alarm rings.

### UAT-D4 — Diagnostics report is accurate and redacted
- **Steps:** Privacy & data → Diagnostics → Export diagnostics.
- **Collect:** the report text. Assert: permissions match UAT-D3; a Reconciliation line with counts; a Last
  sync time (or "never"); Recent errors section (expected empty in this build). **Search** for raw sensitive
  text — there must be none.
- **Expected:** coarse, accurate, fully redacted.

---

## 5. Onboarding `[SIM]`

### UAT-E1 — First-launch onboarding shows once, before the app's own permission asks
- **Steps:** (1) Delete the app; reinstall; launch. (2) Step through onboarding → Continue to the end.
  (3) Force-kill; relaunch.
- **Collect:** on first launch, screenshot — the **intro is shown first** (the list is not behind it). After
  finishing → the alarm list. After relaunch → **straight to the list** (no onboarding). Export `settings` →
  `hasCompletedOnboarding` = true.
- **Expected:** onboarding appears once on a fresh install and never again; it is not preceded by *app*
  permission dialogs.
- **Note (known, device):** iOS/AlarmKit may show its **own** notification-permission prompt at launch
  (alarms are delivered via notifications). Record whether it appears and when; it is framework behavior, not
  app view ordering.

---

## 6. Conversational AI create `[DEVICE for real parse; SIM for fail-closed]`

### UAT-F1 `[SIM]` — Fail-closed when the on-device model is unavailable (#33)
- **Steps:** + → *Describe your alarm* → type "wake me at 7 tomorrow" → Set up.
- **Collect:** the resulting state — on the simulator (no FoundationModels) it must show **"couldn't set that
  up automatically… enter it manually"** and the **Enter manually** button must work. Screenshot.
- **Expected:** no fabricated alarm; a one-tap manual fallback.

### UAT-F2 `[DEVICE]` — Real natural-language create (eligible device)
- **Steps:** + → *Describe your alarm* → "weekdays at 6:30" → Set up → review the **preview** → Confirm.
- **Collect:** the previewed schedule (time + repeat + time zone assumptions), then **export** → the created
  alarm's `schedule` must match the preview and be `criticality: standard` (parsed text never yields a
  critical alarm). Try "make it a critical alarm at 6" — assert the result is **standard**, not critical.
- **Expected:** the preview matches the request; Confirm creates exactly that alarm; never critical from text.
- **FAIL if:** a parsed alarm is created critical, or is scheduled before Confirm.

---

## 7. Readiness `[DEVICE for data; SIM for degraded]`

### UAT-G1 `[SIM]` — Degrades safely with no data (#36/#38)
- **Steps:** Readiness (bed icon) → allow/deny Health.
- **Collect:** the card state — with no sleep data it must show **"not enough data"** (no fabricated score);
  screenshot.
- **Expected:** never a number without data; the rest of the app is unaffected.

### UAT-G2 `[DEVICE]` — Real readiness from Health
- **Pre:** device with recent sleep in Health; grant Health read.
- **Collect:** the readiness **level** + **certainty** + the contributing factors; screenshot. Deny Health and
  re-open → it must degrade to "not enough data", never crash.
- **Expected:** a coarse estimate with certainty; **no diagnostic/treatment language** anywhere (#39).

---

## 8. Travel / time zone `[DEVICE]`

### UAT-H1 — Background zone change corrects the alarm live
- **Pre:** a wall-clock recurring alarm; note its next-ring time. Change the device time zone (Settings, or
  travel) **while the app is backgrounded**.
- **Collect:** the alarm's next-ring time before vs after (should re-anchor to the new zone); Diagnostics →
  a reconcile occurred; the audit shows a `systemReconciliation` event.
- **Expected:** the schedule re-computes for the new zone without needing to foreground first.

---

## 9. Accessibility `[DEVICE or SIM]`

### UAT-I1 — VoiceOver
- **Collect:** with VoiceOver on, sweep the alarm list — each row announces a single phrase leading with
  criticality, then label/status/next-ring; the **Delete** swipe announces the ring **consequence** (not a
  bare "Delete"). Record the spoken strings.
- **Expected:** nothing is icon-only; destructive actions speak their consequence.

### UAT-I2 — Dynamic Type + Reduce Motion + contrast
- **Collect:** at the largest accessibility text size, screenshot each screen — no truncation/overlap; status
  is conveyed by label+icon (not color alone); with Reduce Motion on, the challenge progress steps rather
  than animating continuously.
- **Expected:** all readable + operable; no color-only meaning.

---

## 10. Reliability soak `[DEVICE]`

### UAT-J1 — Overnight reliability + battery
- **Steps:** schedule alarms across a night; leave the device idle.
- **Collect:** each ring's scheduled-vs-actual delta; overnight **battery %** delta (compare to
  `docs/BATTERY.md` budgets: alarms ≤1%, +location ≤0.5%, +health ≤0.3%, +pre-alarm ≤0.5%); any missed ring.
- **Expected:** every alarm rings on time; battery within budget; zero missed rings.

---

## Reporting

For each test record: **ID, tier, result (Pass/Fail/Blocked), the collected data/artifacts, and notes.** File
one **data export** and one **diagnostics export** per session as the session's evidence bundle. Any FAIL on
a `[DEVICE]` safety item (C1, C2, H1, J1) blocks release; a FAIL on a privacy item (D1/D2/D4) blocks release.
