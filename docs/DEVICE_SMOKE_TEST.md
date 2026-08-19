# Real-Device AlarmKit Smoke Test (WG-031)

AlarmKit scheduling, ringing, and the critical-alarm guarantees **cannot be exercised in
the simulator or the unit suite** — they depend on the real system alarm authority, the
lock screen, silent/Focus/DND state, background termination, and reboot. This checklist is
the on-device gate that covers what the automated tests defer (WG-025 authorization,
WG-026 mapping + critical baseline, WG-029 reconciliation, WG-030 schedule/cancel/snooze).

Run it **once per release build** and whenever the deployment iOS version changes. Every
case has evidence fields — record the actual observed behavior and attach a screenshot or
screen recording. A **Fail on any case marked (safety-critical) blocks the release.**

> Safety framing: an alarm must ring even if the app crashed, was force-quit, the device
> rebooted, no `BGTaskScheduler` run occurred, or the phone is in silent/Focus/DND
> (critical alarms) — SAFETY_INVARIANTS #9/#10. The app must never assume an external
> operation happened or did not happen without reconciling against the system (#10).

---

## Run metadata (fill per run)

| Field | Value |
| --- | --- |
| Date / time zone | ______ |
| Tester | ______ |
| Device model | ______ |
| iOS version | ______ |
| App version / build | ______ |
| Commit SHA under test | ______ |
| AlarmKit authorization state at start | ☐ notDetermined ☐ authorized ☐ denied ☐ restricted |
| Overall result | ☐ Pass ☐ Fail ☐ Blocked |

Each case records: **Result** (☐ Pass ☐ Fail ☐ Blocked), **Observed** (what actually
happened), **Evidence** (screenshot / recording / log reference), **Notes**.

---

## A. Authorization (WG-025)

### SMK-01 — First-run authorization prompt appears after an explanation
- **Preconditions:** fresh install, AlarmKit `notDetermined`.
- **Steps:** 1. Reach the first alarm-scheduling action. 2. Observe the in-app explanation precedes the system prompt. 3. Grant.
- **Expected:** the explanation is shown *before* the OS prompt; granting moves state to `authorized`; the alarm schedules.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

### SMK-02 — Denied authorization keeps the last safe state and offers Settings
- **Preconditions:** deny the prompt (or pre-set Denied in Settings).
- **Steps:** 1. Attempt to schedule. 2. Observe the denied-path UI. 3. Confirm any previously scheduled alarm is unchanged.
- **Expected (safety):** no crash; a clear message stating whether existing alarms remain scheduled; a deep link to Settings; **no existing alarm is silently dropped** (#10).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

---

## B. Schedule, ring, and actions (WG-026, WG-030)

### SMK-03 — A scheduled alarm rings on the lock screen
- **Steps:** 1. Schedule a one-time alarm ~2 min out. 2. Lock the device. 3. Wait.
- **Expected:** the alarm rings at the correct minute on the lock screen with the correct label.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

### SMK-04 — (safety-critical) A critical alarm rings through silent, Focus, and DND
- **Preconditions:** create a **critical** alarm; set the ringer switch to silent, enable a Focus, and enable Do Not Disturb.
- **Steps:** 1. Schedule the critical alarm ~2 min out. 2. Lock. 3. Wait, with silent + Focus + DND all active.
- **Expected (safety-critical):** the critical alarm **rings audibly through all of silent / Focus / DND**. (AlarmKit has no app-facing criticality knob — WG-026 assumes the system-alarm baseline provides this; **this case is the verification**.) A standard (non-critical) alarm's behavior under silent is recorded for contrast.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

### SMK-05 — Alarm actions (stop / snooze) behave correctly at the ring
- **Steps:** 1. At a ringing alarm, exercise each presented action (stop; snooze if offered). 2. Observe re-fire timing for snooze.
- **Expected:** stop ends the ring; snooze re-fires at the expected offset; the label is retained. Note whether snooze is presented (processor-level snooze is not yet wired — WG-073).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

### SMK-06 — Cancel: a cancelled alarm does not ring
- **Steps:** 1. Schedule an alarm ~2 min out. 2. Cancel it (disable) before it fires. 3. Wait past the fire time.
- **Expected:** the alarm does **not** ring; the UI shows it disabled; the next-ring summary updates.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

### SMK-07 — Edit reschedules to the new time
- **Steps:** 1. Schedule an alarm. 2. Edit its time. 3. Confirm the old time does not fire and the new time does.
- **Expected:** only the new occurrence fires; no duplicate ring at the old time (idempotent reschedule on the alarm id).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

---

## C. Persistence across app lifecycle (SAFETY_INVARIANTS #9, #10)

### SMK-08 — (safety-critical) Alarm rings after the app is force-quit
- **Steps:** 1. Schedule an alarm ~3 min out. 2. Force-quit the app (swipe up from the app switcher). 3. Wait.
- **Expected (safety-critical):** the alarm **rings** while the app is terminated — no `BGTaskScheduler` run is required (#9).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

### SMK-09 — (safety-critical) Alarm rings after a device reboot
- **Steps:** 1. Schedule an alarm ~5 min out. 2. Power off and restart the device (do not unlock past the first boot lock if testing pre-unlock behavior; note which). 3. Wait.
- **Expected (safety-critical):** the alarm **rings** after reboot. If iOS requires a first unlock, record that constraint explicitly.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

### SMK-10 — Repeated / recurring alarm fires on consecutive occurrences and re-arms
- **Steps:** 1. Schedule a daily (or minutely-for-test) recurring alarm. 2. Let it fire, stop it, and confirm the next occurrence is armed. 3. Repeat for at least two consecutive occurrences.
- **Expected:** each occurrence fires; after each ring the next occurrence is re-armed (per-occurrence scheduling, WG-026) without reopening the app.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

---

## D. Reconciliation (WG-029)

### SMK-11 — Launch/foreground reconciliation repairs a divergence
- **Preconditions:** requires the launch/foreground reconcile trigger to be wired (follow-on). If not yet wired, mark **Blocked** and record the blocking task.
- **Steps:** 1. Schedule alarms. 2. Induce a divergence (e.g., force-quit mid-schedule to strand an operation, or otherwise cause a missing/extra/divergent system alarm). 3. Relaunch / foreground.
- **Expected:** a **missing** alarm is re-scheduled, an **extra** one is cancelled, a **divergent** fire time is corrected; a `systemReconciliation` entry appears in the audit history; a currently-ringing alarm is **never** cancelled by reconciliation (#24).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

### SMK-12 — Criticality survives a reconciliation pass (isCritical read-back seam)
- **Steps:** 1. Schedule a **critical** alarm. 2. Trigger reconciliation (relaunch/foreground). 3. Repeat across two passes.
- **Expected:** the alarm stays **critical** after reconciliation and is **not** needlessly re-scheduled every pass. If the AlarmKit read-back cannot report criticality, record it here — the planner would then see every critical alarm as divergent and redundantly re-schedule (WG-026/WG-029 seam to resolve before this passes).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

---

## E. Audit and error surfacing (SAFETY_INVARIANTS #46–#50, quality rules)

### SMK-13 — Every mutation and repair appears in a user-understandable history
- **Steps:** 1. Create, edit, disable, and (if triggered) reconcile alarms. 2. Open the history view (when built).
- **Expected:** each action has an entry with actor (user vs `systemReconciliation`), reason, and timestamp; recovery/reconciliation entries are distinguishable from ordinary edits (#50). If the history UI is not yet built, mark **Blocked** with the task.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

### SMK-14 — An error message states whether the alarm remains scheduled
- **Steps:** 1. Induce a failure (e.g., revoke authorization mid-flow, or airplane mode during an operation). 2. Read the error UI.
- **Expected:** the message tells the user what happened **and** whether the alarm is still safe/scheduled; no sensitive raw data is shown (#41).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

### SMK-15 — Edit / enable-disable / delete from the list, with destructive confirmation (WG-043)
- **Steps:** 1. Toggle an alarm off then on (enable/disable). 2. Tap a row to edit its time/label and Save. 3. Swipe a row and tap Delete — verify a **full swipe does not delete in one gesture**. 4. Repeat delete / disable / edit on a **critical** alarm and read the confirmation prompt; cancel it, then confirm it. 5. With VoiceOver on, focus a row's toggle, the delete action, and the confirm/cancel buttons.
- **Expected:** each action routes through the command processor and updates the list; a **critical** alarm's delete/disable/edit shows a confirmation prompt, and **cancelling leaves the alarm unchanged** (#6, no-response = no change); no one-gesture full-swipe delete; VoiceOver announces the alarm name + the on/off consequence and the destructive action (not color-alone); an error states whether the alarm is still scheduled (#41 coarse). Alarms stay **saved-but-not-ringing** until the AlarmKit adapter lands (disclosure banner visible). Known: editing a **past** one-time alarm may report "can't ring yet" on Save — pick a future time.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

---

## F. Overnight movement estimate (WG-310–313)

### SMK-16 — The "Movement overnight" section reports the same night however often the screen is opened

> **Fail conditions added 2026-08-19 (round ten).** Record a **Fail** if the disturbance line claims anything
> about the night as a whole (it must scope itself to the rest stretch — the count excludes any awakening of
> 20 minutes or longer, so "No overnight movement detected." was false on the worst nights); if the
> no-night-found line asserts a shortage of *data* rather than describing the *pattern*; or if a rest line and
> a disturbance line disagree (a short night reported as undisturbed is the H4 signature and is expected on
> this build — note it, do not file it as new). **Also measure and record** how long the movement section
> takes to resolve on the slowest device available: that observation, not this ADR, should set the final
> value of the 15s deadline.
- **Steps:** 1. Carry the phone normally for a full night (grant Motion & Fitness; the history query is foreground-only and needs a **real device** — the simulator has no motion history). 2. In the morning, open Readiness and record the rest window and pickup count. 3. Leave the app, move around / commute, reopen Readiness **at least twice more** across the morning and re-record. 4. Repeat once with the phone left charging **across the room** overnight. 5. Repeat once after **travelling across a time zone**, and once on a **DST-transition** night if the calendar allows. 6. On a **desk-bound day** — phone left still on a desk for most of the afternoon — reopen Readiness at roughly **17:00 and again at 21:00** and re-record. 7. **Grant Motion & Fitness for the first time in the morning**, so the history holds almost nothing, and open Readiness.
- **Expected:** the numbers are **identical** across every open in step 3 — the section describes last night, so morning activity and the commute must not sweep in and the rest window must not shrink (WG-313; before the fix it drifted on every open). The section stays reachable **all day**, not only in the morning, and does not vanish at 18:00 local. **Steps 6 and 7 are both expected to FAIL today** — they are the device reproductions for the two open WG-313 defects, so record what you observe and do **not** file either as a new bug. **Step 6 is WG-313 H2:** the afternoon at the desk may be reported as "last night" and the two reads may disagree, because candidate blocks are ranked by raw duration and a still desk has the same motion signature as a bed. **Step 7 is WG-313 H3:** a nearly-empty history *should* report the section as unavailable, but a single stale record currently fabricates a confident multi-hour night with zero disturbances — that is the defect, not a regression. Both are blocked on **WG-317** (evidence coverage); file nothing unless you see a shape *not* described here. Step 4 legitimately reports a different night or no night — a phone across the room reports what *it* experienced, which is a known limitation of the estimate, not a failure. Time-zone and DST nights still resolve a night (the anchor is local wall-clock, durations are elapsed time). Throughout: the "Estimated from movement — not measured sleep." caveat is visible, no times-of-night are shown (#41), and nothing in this section changes the readiness score above. Denying or revoking Motion access **keeps the section visible and states why** (WG-318) — it must never hide, and never show a stale or zeroed value. Check the wording matches the cause: a device with no motion hardware reads "This device can't track movement" — **device-neutral wording, and an iPhone name or an iPhone glyph here is a Fail**: the target ships to iPad (`TARGETED_DEVICE_FAMILY: "1,2"`), most iPads have no activity classifier, so this is the *only* state an iPad user ever reaches in this section; a denied or not-yet-granted grant reads "Alarm Agent doesn't have access to your movement data" — **the display name; "WakeGuard" is the internal `PRODUCT_NAME` and appears in no other user-facing string, so seeing it on screen is a Fail** (this checklist line itself quoted the stale name until 2026-08-18, which would have turned a correct build into a recorded Fail); a restricted (MDM / parental-controls) device is told Settings won't change it; a transient read failure says so **without** instructing a retry this screen cannot perform (there is no pull-to-refresh); and history that resolves no night reads "We couldn't pick out a clear rest period last night." Reporting a denied grant as "not enough data", or any of the others as a Settings problem, is the failure this step exists to catch. **The same device-neutrality rule applies to the *success* lines**, which sat outside every copy check until 2026-08-18: the disturbance line reads "Movement detected N times overnight" with a walking glyph — "Phone moved…", or the `iphone.gen1.radiowaves.left.and.right` glyph (CoreGlyphs restricts it to Apple's iPhone), is a **Fail**. **No state in this section carries a warning triangle**, including the denied grant: none of them offers an action this screen can perform, so a triangle would be an alarm with no remedy behind it — seeing one is a **Fail**. **On every open, watch the section in the first moment the card appears:** the motion query starts only after the card is already on screen, so the section must show its header with "Checking your movement…" and then resolve to one of the outcomes above. A gap under the header — even a brief one — is the WG-318 defect the section exists to prevent and **is** a Fail. The query can be fast enough to be hard to catch; record "resolved too fast to observe" rather than marking Pass by assumption. **"Checking your movement…" must never persist past ~15 seconds** (WG-318): the CoreMotion completion handler carries no delivery guarantee, so the view model abandons the read at a deadline and shows "We couldn't read your movement data just now." A spinner still on screen after 30s is a **Fail** — the screen has no pull-to-refresh, so it would never resolve. **Time this on the slowest device available and on a night with a large history**, since a deadline set too tight would instead show that failure message for a read that was about to succeed; record the observed resolve time either way, as that number is the only evidence for the 15s choice.
- **Known limitation (not a failure):** opening the screen **mid-sleep** does still report a shorter night — the night is not over yet, so the longest quiet block genuinely is shorter than it will be by morning. A morning of short movements separated by sitting can likewise stretch the reported night (WG-313 **H2**, open). Record either, do not file it.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Evidence:** ______ · **Notes:** ______

---

## Sign-off

| | |
| --- | --- |
| All safety-critical cases (SMK-04, SMK-08, SMK-09) pass | ☐ Yes ☐ No |
| Blocking failures / blocked cases (list IDs + reason) | ______ |
| Follow-up tasks filed | ______ |
| Tester sign-off | ______ |
| Date | ______ |
