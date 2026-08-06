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

## Sign-off

| | |
| --- | --- |
| All safety-critical cases (SMK-04, SMK-08, SMK-09) pass | ☐ Yes ☐ No |
| Blocking failures / blocked cases (list IDs + reason) | ______ |
| Follow-up tasks filed | ______ |
| Tester sign-off | ______ |
| Date | ______ |
