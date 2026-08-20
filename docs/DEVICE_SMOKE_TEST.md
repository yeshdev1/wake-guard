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

## F. Overnight movement estimate and readiness card load (WG-310–313, WG-318, WG-319)

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

### SMK-17 — The readiness card resolves to something readable, and never to a claim about data it did not read

> **Added 2026-08-19 (WG-319).** `ReadinessViewModel` cited this check before it existed. SMK-16 covers the
> movement *section* inside the card; this covers the **card itself**, which is one layer up and hides
> strictly more when it fails — including the always-on movement section SMK-16 is written to verify. Run
> SMK-16 first: if the card never appears, every SMK-16 observation is vacuous.

- **Precondition — check this before step 1 or the decisive Fail condition below is unusable.** The device needs at least one night of **`Asleep`** sleep data **dated inside the last 14 days**. Both halves are load-bearing and neither is visible from "there is sleep data in Health": `SleepMetrics.asleepDuration`, `.asleepByNight` and `.sleepMidpoint` all filter `category == .asleep`, so a store holding only **In Bed** samples — the ordinary case for an iPhone-only user on Sleep Focus with no Apple Watch — yields `lastNightAsleep`/`consistency`/`debt` all `nil`, i.e. an assessment with **zero factors**; and `ReadinessViewModel`'s `lookback` defaults to **14 days**, with `.strictStartDate` in the adapter, so older nights are correctly invisible. Either alone renders the exact "not enough data" card that step 6 and the Fail condition treat as a signal. Confirm in Health → Browse → Sleep that you see **Asleep** rows (not only "Time in Bed") inside the window. If you cannot, record **Blocked** — do not proceed to the Fail condition.
- **Steps:** 1. Open Readiness on a device meeting the precondition above and watch the first moment after the screen pushes. 2. Record how long "Checking your sleep readiness…" is on screen before the card replaces it. **Start the clock when the Health permission sheet is dismissed.** On a run where **no sheet appears**, the clock you can actually start (screen push) measures something different from the bound below — see the threshold note. 3. Navigate back to the alarm list and re-enter Readiness several times, including immediately after a cold app launch. 4. Repeat on the **slowest device available**, and on the account with the **largest** Health history you can reach — a 14-day query over a dense store is the realistic worst case. 5. Re-open while Health is **syncing after a restore**, if you can arrange one — that is the realistic way to make an `HKSampleQuery` slow. 6. **Revoke** Health sleep access in Settings → Privacy & Security → Health → Alarm Agent, then return to the app, **pop back to the alarm list, and push Readiness again** — see the note below on why backgrounding alone is not enough. 7. Open Readiness and **navigate away within the first second**, before the card appears; return and confirm the screen recovers. **Read the step-7 note before recording it — it does not observe WG-319.**
- **Expected:** the spinner belongs to a query that is genuinely in flight and to nothing else. It **must resolve** — to a readiness card, or to "We couldn't check your sleep readiness just now."
- **Threshold.** The bound is **15s** (`sleepTimeout`), and **15s is what a *correct* build's worst case looks like** — when the deadline does its job it fires at t≈15.0s and the card renders a few milliseconds later. So the Fail line has to sit strictly **above** the bound, or a working deadline lands on it and a stopwatch cannot tell the two apart: **resolve by ~15s is a Pass; still spinning at 20s is a Fail.** 15s is `sleepTimeout` alone, **not** the composed 30s: `refresh` awaits the sleep read to completion, and `applySleepRead` **exits `.loading` on every branch** (`.samples` assigns `.assessed`; the failure arm either assigns `.unavailable` or breaks out of a state that is already not `.loading`) — so the card is on screen before the movement read starts. Read that as "departs from `.loading`"; an earlier version wrote "leaves `.loading` in *every* branch", which also reads as "leaves it *as* `.loading`" and inverts the whole correction. The further 15s `movementTimeout` bounds the **"Checking your movement…" spinner inside the already-visible card**, which is SMK-16's measurement, not this one. Do not apply the 30s number here — it is the bound on `refresh` *returning*, and an earlier version of this line used it as the threshold, which would have passed a 20-second spinner that is a genuine WG-319 regression.
- **What the 15s is measured from, and why step 2's clock may not measure it.** The bound runs **from the start of `refresh`**, which is *after* `ReadinessScreen`'s **unbounded** `requestAccess()` — a wait WG-319 deliberately scoped out. On a run where the sheet appears and is dismissed, the two coincide closely enough and the threshold applies as written. **On a no-sheet run the only clock a tester can start (screen push) includes that unbounded wait, so the threshold does not apply**: a spinner past 20s there is **Blocked, not Fail**. Apply the discriminator in the note below before recording anything.
- **Record the observed resolve time in step 4 either way, including on a Pass** — that measurement, not the ADR, is the only evidence for the **15s `sleepTimeout`** (SMK-16 is the corresponding evidence for `movementTimeout`; this step observes only the sleep read and must not be used to set both).
- **The decisive Fail condition is a false claim, not a slow one:** if the card says "There isn't enough sleep data yet", "Add a few nights of sleep data and this will get more useful.", or lists factors as missing **on a device meeting the precondition above** — **first confirm in Settings → Privacy & Security → Health → Alarm Agent that sleep access is still ON**, because step 6 deliberately produces this exact screen and an access reset from a restore or an earlier run would otherwise be filed as a phantom WG-319 regression. **Then re-check the precondition itself** — an In-Bed-only store, or a store whose newest `Asleep` night is more than 14 days old, produces this card *correctly*, and "there is sleep data in Health" does not distinguish either from the defect. With access confirmed on **and** the precondition confirmed met, it is the defect WG-319 exists to remove and is a **Fail**: a read that returned nothing must never be reported as the user having nothing.
- **Step 7 is a recovery check, not a WG-319 check — record it, do not read it as evidence for the deadline.** It must recover, and a permanently blank or permanently spinning card after a return is worth filing. But it passes for a reason that has nothing to do with the cancellation path: `ReadinessScreenContent` owns its model in `@State` and `AlarmListView` pushes it via `NavigationLink`, so popping destroys the model and re-pushing builds a fresh one at `.loading` and re-runs `.task`. That happens even if the `.cancelled` arm is deleted outright — the `.unavailable` it writes on cancellation goes into a model whose view is already gone and is never rendered. On a device meeting the precondition the query also usually returns in well under a second, so "navigate away before the card appears" is a race you will often lose: record **"resolved too fast to observe"** rather than ticking Pass by assumption.
- Throughout: the movement section is still present inside the card in **every** outcome, including the unavailable one — a failed *sleep* read that hides the movement section is a Fail (it is the WG-318 guarantee collapsing from one layer up).
- **Step 6 is expected to FAIL on this build and must not be filed as new.** A revoked or denied grant is reported as a data shortage. The cause is **not** that the screen discards an answer it could have used — an earlier version of this line said that, and it was false. `HKHealthStore.requestAuthorization` does not throw on Don't Allow, so the adapter reports `.authorized` for Allow and Don't Allow alike, an unauthorized read simply returns an empty sample set, and **no layer in this app can distinguish a denial from a genuinely empty store.** That is Apple's design. **WG-320** therefore fixes the *copy* on that path rather than the plumbing; record what you see and move on. Note also that step 6 requires a **pop and re-push**, not just backgrounding: `ReadinessScreen` has no scene-phase hook and its `.task` does not re-run on foreground, so a revocation performed while Readiness is still on screen leaves the previous card up unchanged — which is itself worth recording, since a stale readiness claim survives a revocation for as long as the reader stays put.
- **If the screen is stuck with no sheet and no card, this checklist cannot tell you which defect you are looking at.** Three different things present identically: a wedged Health daemon inside the **unbounded** `requestAccess()` (a stated WG-319 limitation, not a defect to file), a genuine failure of the 15s deadline (a Fail), and — on any run after the first — the ordinary case where no sheet appears because authorization is already determined. There is no on-device discriminator in this build. The one external check worth doing: open **Health.app** and any other Health-reading app; if those hang too, it is the daemon, not us. Record which you observed and how you concluded it.
- **Coverage gap on device — no step here produces the `.unavailable` card (closed at the UI layer; see the paragraph below).** Steps 1–4 produce a normal card, 5 a *slow* card (slow is not the same as past the deadline), 6 the empty-data card, 7 a rebuild. None of them renders "We couldn't check your sleep readiness just now." on a device, so **no step here reaches it and none should be attempted** — forcing it requires a >15s or erroring `HKSampleQuery`, which no user action reliably produces. Do not record a Fail for not seeing this card.
  **Closed at the UI layer 2026-08-20 by WG-322**, which is where this gap belonged all along: `-uiTestingSleepReadFails` composes a throwing sleep read and `testTour7ReadinessSleepReadFailed` asserts the card, so `readinessUnavailableReason` and `readinessLoading` are now referenced, the branch is rendered under assertion, and there is a reference screenshot (`19-readiness-sleep-read-failed`) a human can finally look at. **Verified by re-applying the M4 mutant** (`cardContent`'s `.unavailable` arm → `return nil`): the tour case fails on the assertions that describe the defect — no card, spinner still up, movement section gone. Note those three are **structurally correlated**, not three independent observations: the spinner is the `else` of the same `if let` that yields the card. The sharper check is **M13** (2026-08-20), which replaces the card's `Label(reason.message, …)` with "There isn't enough sleep data yet.": it **survives all 1449 unit tests** and dies only in the tour, because the tour now asserts the rendered sentence rather than the presence of its identifier. If you are hand-checking this card, read the words — the identifier being present is not the claim. **This note previously prescribed "a never-answering sleep query"; that was the wrong build.** A hang reaches the same arm only after `sleepTimeout`, costing 15s the tour must wait, and `ReadinessScreenContent` builds its view model with the default timeout so the graph has no seam to shorten it — whereas `applySleepRead` routes `.failed` and `.timedOut` into the *same* arm, so a throw lands there instantly. The deadline itself is covered at the unit layer; what was uncovered was the rendering. Note `make test-ui` still runs in neither `ci` nor `ci-fast`, and **as of 2026-08-20 it cannot: the target is red for an unrelated, pre-existing reason** — all six `CoreAlarmFlowsUITests` drive an `addAlarmButton` that no longer exists in `Sources/`, filed as **WG-323**. All seven tours pass.
- **Known limitation (not a failure):** the screen offers **no retry**. "We couldn't check your sleep readiness just now." describes a transient state and gives the reader nothing to do about it but leave and come back, which nothing on screen says. Record it; it is filed, not overlooked.
- **Known limitation (not a failure), and there is deliberately no step for it:** on a **restricted** device (MDM / parental controls) that same sentence is outright false — the failure is permanent, not "just now". `requestAuthorization` throws, the adapter fails closed to `.restricted`, `ReadinessScreen` discards that result, and the query then errors into the one unavailable case. The sibling movement section *does* distinguish this ("Settings won't change this"); the sleep path collapses it. Filed as **WG-321**. If you happen to be testing on a supervised device, record what you see rather than filing it.
- **Copy note:** the two quoted sentences above are transcribed from `ReadinessUnavailability.message` (`Sources/WakeGuardApp/ReadinessDisplayState.swift`). They were quoted wrongly when this check was written — as "We couldn't read your sleep data just now.", which is not only absent from the product but contains the substring `sleep data` that `ReadinessDisplayStateTests` explicitly forbids any unavailability message from containing. **Re-check these quotes against source whenever the copy changes**; a stale quote here turns a correct build into a recorded Fail, exactly as SMK-16 records happening to itself. **Also check the disclaimer line at the foot of the card**, which now reads "Sleep estimates here help you plan — they are not a diagnosis." It is rendered outside both switches, so it appears in every branch — including one where nothing on the card is an estimate — and its previous wording ("A sleep estimate to help you plan — not a diagnosis.") asserted an artefact that branch does not contain. **Nothing pins this string at any layer:** it is a literal inside `ReadinessCardView` (which is what keeps it localizable — moving it to a `String` constant would silently select the non-localizing `Text` overload, the defect `ReadinessUnavailability.message` already has), its `readinessDisclaimer` identifier is referenced by no test, and the note is required by #39 / `PRODUCT_SPEC.md:65`. So this checklist line is currently the **only** thing guarding it: if the foot of the card is bare, that is a **Fail**.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked · **Observed:** ______ · **Resolve time (step 4):** ______ · **Evidence:** ______ · **Notes:** ______

---

## Sign-off

| | |
| --- | --- |
| All safety-critical cases (SMK-04, SMK-08, SMK-09) pass | ☐ Yes ☐ No |
| Blocking failures / blocked cases (list IDs + reason) | ______ |
| Follow-up tasks filed | ______ |
| Tester sign-off | ______ |
| Date | ______ |
