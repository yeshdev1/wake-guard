# WakeGuard — Commitment Lock + Relentless Re-arm Plan (WG-287…294)

Status: **approved 2026-08-13** (product owner — the invariant-#6 amendment is explicitly approved; ADR in
`DECISIONS.md`): a critical walk-challenge alarm that is not cancelled **at least 1 hour before it fires**
becomes **locked** — it cannot be deleted, disabled, delayed, or weakened — and once it rings, **stopping
without completing the challenge just makes it ring again**, relentlessly, for **30 minutes**, then it
stops for good (the safety bound). The walk (or the accessible alternative) is the only true exit. Extends
`docs/CHALLENGE_RING_PLAN.md` (WG-280–286).

Additional product decisions (2026-08-13):
- **The 30-minute bound is confidential** — a company-side parameter. **No user-facing surface** (copy,
  UI, countdowns, cycle counters, marketing) may disclose the bound or the cycle cadence, in either
  direction: no "for 30 minutes", and equally no "forever/until you walk" over-claim a user might rely on.
  User-facing copy says only: *"WakeGuard keeps re-ringing if you stop without completing the walk."* The
  bound lives in the ADR, the code, and internal docs only.
- **Uninstall deterrent** — shown in-app on locked alarms (iOS provides **no uninstall hook**, so nothing
  can be shown at uninstall time). The copy must be the **honest** deterrent: *"Deleting WakeGuard erases
  all of your alarms, history, and settings — they cannot be restored."* (True: local-only storage, no
  backend.) A "you would have to pay again" claim is **not shippable**: App Store re-downloads and
  purchase restores are free and Apple-mandated, so the claim would be false — a dark pattern and an App
  Review rejection risk. If a paid tier ever exists, restore is still required; the data-loss framing is
  the strongest deterrent that is true.
- **Power-off resilience** — required behavior: if the phone is switched off during the ring window and
  switched on again, the app must ring or stay silent based on elapsed time since the fire and whether the
  walk was recorded. Delivered **structurally** by the pre-scheduled chain (§2): AlarmKit alarms persist
  across reboot, so chain entries whose fire times are still in the future ring after power-on with no app
  involvement; entries missed while off stay missed; a recorded pass cancelled the chain before power-off.
  App-side, launch reconciliation (WG-292) re-verifies the remaining chain whenever the app next opens
  inside the window. (The window runs from the **fire time**, and the app cannot run itself at power-on —
  iOS launches nothing — which is exactly why the chain, not app logic, carries this guarantee.)

---

## 1. Context — what exists and what was proven on-device (as of 2026-08-13)

**Device-verified working** (free-team branch `local/freeaccount-device-test`, iPhone 17 Pro Max, iOS 26.2):
- AlarmKit alarms schedule, ring, and show **Stop + "Start walk"** (WG-281).
- "Start walk" opens the app **into the walk challenge** without stopping the ring (WG-282).
- Motion & Fitness is requested in-context; steps count live (WG-061 fix).
- **Blocked on calibration:** a real walk fills the bar but doesn't *pass* — the anti-shake gate
  (`CadenceThresholds.minimumIntervals: 8`) is uncalibrated for real CMPedometer delivery. A DEBUG cadence
  readout is on the challenge screen (WG-075); **awaiting the user's walk + shake readings** to set the
  thresholds. **This calibration is a hard predecessor** — enforcing a walk that cannot pass would trap
  users on the accessible fallback for 30 minutes.

**Built + CI-tested, not yet wired to the real ring:**
- `RearmPolicy` (pure, WG-283): re-arm every **2 min up to 15 cycles (~30 min) → stop**. The default
  already equals the approved bound. Cap unit-pinned ("the alarm always ends").
- `ChallengeRearmCoordinator` (WG-284): critical-only tracking, pass → clear, stop-without-pass → re-arm
  via ports (`PendingChallengeStore`, `ChallengeReArming`), cap → stop. Fakes-tested.

**Platform ceilings (design premises, from ADR WG-285):**
- AlarmKit **mandates a Stop button** — the ring itself can never be un-dismissable. Enforcement = make
  Stop *pointless*, not impossible.
- **Invariant #9: "A background task is never required for an alarm to ring."** The app is usually **not
  running** when the user taps Stop on the lock screen — so a *reactive* re-arm (app observes the stop,
  then schedules) can be silently defeated by simply never opening the app. This forces the load-bearing
  design decision below.

---

## 2. The load-bearing design: a **pre-scheduled follow-up chain**, not reactive re-arm

> If the app can't be guaranteed to run at stop-time, the re-rings must already exist in the system.

When a locked critical walk alarm is scheduled, the app schedules the **main alarm + a chain of follow-up
AlarmKit alarms** at +2, +4, … +30 minutes — all upfront, all carrying the same "Start walk" intent
(payload = the parent alarm id). Then:

- **User taps Stop and ignores the app** → nothing to defeat: the next chain alarm is already scheduled by
  the OS and fires 2 minutes later. Repeat to the 30-minute bound. **No background execution needed (#9).**
- **User passes the challenge** (walk or accessible alternative) → the pass, which by definition happens
  *in the app*, stops the alerting alarm **and cancels every remaining chain entry**. Silence.
- **The 30-minute bound is structural**: the chain is finite (15 entries). Even if the app never runs
  again, the ringing ends. The cap is enforced by *what exists in the system*, not by app logic.

`ChallengeRearmCoordinator` remains the in-app brain (pass → cancel chain; attempts accounting; cleanup on
launch), but the *relentlessness* no longer depends on the app being alive.

Chain mechanics:
- **Deterministic chain IDs**: derived from (parent UUID, index) via a stable hash — idempotent
  re-scheduling, recognizable by the reconciler, no random source (determinism rules).
- **Desired-state integration**: the pure planner's "desired system alarms" for a locked critical walk
  alarm = main occurrence **+ its unexpired chain entries while the wake is unsatisfied**; a satisfied wake
  (pass recorded) ⇒ chain entries are *undesired* ⇒ the existing reconciler (WG-029) cancels leftovers
  naturally on next run. No parallel bookkeeping system.
- **Ring-stop mapping**: a pass must stop whichever ID is *currently alerting* (parent or a chain member)
  and cancel the rest — the stop path takes the family, not just the parent id.
- **AlarmKit alarm-count limit**: `maximumLimitReached` exists; the real cap is unknown. **Device probe in
  WG-291.** Fallback if 16/alarm is too many: schedule a shorter upfront chain (e.g. 5 = 10 min) and extend
  it each time the app opens (every "Start walk" tap extends); the 30-min bound then holds whenever the
  user engages at all, and degrades gracefully (documented) when they never do.

## 3. The commitment lock

Pure domain rule (no persistence needed — derived from now + the resolved next fire instant):

```
locked(alarm, now) =
    alarm.criticality == .critical
    && alarm.challengePolicy.isRequired
    && alarm.isEnabled
    && nextFire(alarm) - lockWindow <= now < wakeSatisfiedOrBoundEnd
lockWindow = 60 min (constant, not user-configurable below the floor)
```

Enforced in `DefaultAlarmPolicyEngine` (the existing `isDestructive` / `needsConfirmation` seam): while
locked, `delete`, `disable`, and any `update` that **weakens** (removes/shrinks the challenge, lowers
criticality, or **moves the fire time** — else editing the time is a trivial escape) is **`.rejected`**
(not `.needsConfirmation`) with honest copy: *"This alarm is locked until you complete its walk. You can
change it after you're up, or before it locks next time."* Everything else about #6 is unchanged; outside
the window the normal confirmation flow applies. Fail-closed: an unreadable alarm/clock rejects the
mutation. Agent/AI commands remain rejected as today (#31).

Edge cases (all in the test matrix):
- **Created/enabled inside the window** → locks immediately; the form discloses it before Save.
- **Strengthening while locked** (raise steps, make earlier?) — *no*: locked means frozen; any update is
  rejected. One rule, no judgment calls at 5 a.m.
- **Time-zone / DST shift during the window** → the lock keys off the resolved *instant*; travel
  re-anchoring recomputes it; hysteresis test pins no flapping.
- **Pre-alarm prompt actions** ("turn off today", "change time") route through the same policy engine →
  rejected while locked (the prompt simply won't offer them, and the engine backstops it).

## 4. Escape hatches — deliberate, enumerated, none silent

| Escape | Handling |
|---|---|
| Accessible alternative (tap/hold) | **Stays.** Required (#21/#22, accessibility law, App Review). It is deliberate effort, not a one-tap out. Optional hardening later: a longer hold for locked alarms — separate decision. |
| 30-minute bound | **Stays** (approved). An alarm that literally cannot end is an emergency hazard. |
| Full data reset (Privacy → Delete everything) | **Stays.** The privacy promise (#42) outranks the lock; it is high-friction (double confirm) and cancels the chain. Recorded in the ADR as deliberate. |
| Uninstall the app | Cannot be prevented (no iOS uninstall hook). Deterred in-app on locked alarms with the **honest** data-loss message (see decisions above) — never a false payment claim. |
| Power off the phone | While off, nothing rings (OS reality). On power-on the **chain entries still in the future ring by themselves** (AlarmKit alarms survive reboot — device-verified in WG-294); a recorded pass already cancelled them. Documented honestly. |
| Tap Stop, never open app | **Closed by the pre-scheduled chain** (§2) — this was the real hole. |

## 5. Safety-invariant change (the reason this needs an ADR)

Invariant **#6** today: *"Critical alarms cannot be cancelled, delayed, or weakened without explicit user
confirmation."* This feature amends it: **within the lock window, a locked critical walk alarm cannot be
cancelled, delayed, or weakened at all** — confirmation is no longer sufficient. That is a deliberate
strengthening-of-enforcement / narrowing-of-user-control on a safety feature ⇒ **ADR + explicit human
approval required** (WG-293), plus updates to `SAFETY_INVARIANTS.md`, the invariant-map test, and the
threat model (new abuse case: "user regrets the commitment" — answered by: the lock was disclosed at
creation, visible for ≥ the entire pre-window, and bounded at 30 min of ringing).

## 6. Phases

| # | Phase | Contents | Verifiable where |
|---|---|---|---|
| **WG-287** | **Anti-shake calibration** *(in flight — hard predecessor)* | Set `CadenceThresholds` from the user's DEBUG walk/shake readings; ADR for the threshold change; device re-test: real walk passes, shake fails | device + CI pins |
| **WG-288** | Commitment lock (domain + policy) | Pure `CommitmentLock` rule; policy-engine rejection of delete/disable/weaken/delay while locked; fail-closed reads; hysteresis + inside-window-create tests | CI |
| **WG-289** | Lock UX | Create/edit form disclosure ("locks at 6:00"), list badge + lock countdown, rejected-action copy, the honest uninstall deterrent on locked alarms, VoiceOver/Dynamic Type per UI rules. **Acceptance: no surface discloses the 30-min bound or cycle cadence** (confidential decision above) | CI + sim |
| **WG-290** | Pending-wake persistence | `PendingChallengeRecord` (schema v6→v7 + migration test), Core Data `PendingChallengeStore` impl, launch cleanup of stale entries | CI |
| **WG-291** | Chain scheduling | Deterministic chain IDs; desired-state = main + unsatisfied chain; processor/adapter schedule + cancel-family; outbox idempotency (revision+fireTime keys already distinct); reconciler treats chain as desired (never reaps a live chain, always reaps a satisfied one); **device probe of the AlarmKit alarm cap** + fallback chain length | CI + device |
| **WG-292** | Device wiring | Alerting observation → `stoppedWithoutPass` when the app *is* running; pass → stop-alerting-member + cancel family; launch reconciliation of a half-consumed chain; chain extension on app-open (if fallback length) | device |
| **WG-293** | ADR + invariant amendment | `DECISIONS.md` ADR; `SAFETY_INVARIANTS.md` #6 amendment; invariant-map + threat-model updates; **human sign-off recorded 2026-08-13** | docs + CI pins |
| **WG-294** | Device matrix + docs | SMK cases below; `TESTABILITY_REPORT.md`/`UAT_PLAN.md`/`IMPLEMENTATION_STATUS.md` updates; port plan to `main` with the feature commits | device |

**Sequencing:** 287 first (blocks honest enforcement). 288–291 are CI-parallel after it; 292 needs a
device; 293 lands **before** 288's policy change merges to `main` (the ADR gates the invariant edit); 294
closes. All work continues on the free-team branch for device testing, then ports to `main` clean (minus
the HealthKit/signing/free-team bits), same as the WG-281/282 flow.

## 7. Test matrix (key cases)

- **Pure lock:** boundary at exactly T−60 min; inside-window create locks immediately; disabled/standard/
  no-challenge alarms never lock; DST/zone shift recompute; clock-jump fail-closed.
- **Policy:** locked delete/disable/weaken/delay → `.rejected` (distinct from `.needsConfirmation`);
  unlocked behavior unchanged (existing pins must not move); agent commands still rejected; unreadable
  store → reject.
- **Chain (CI, fakes):** desired-state includes exactly the unexpired chain while unsatisfied; pass ⇒
  chain undesired ⇒ reconciler cancels; deterministic IDs stable across runs; cap = 15 entries, never
  more; idempotent re-schedule.
- **Coordinator:** unchanged pins + "pass cancels remaining family."
- **Device (SMK additions):** ring → Stop → **rings again ≈2 min later with no app interaction**; repeat →
  chain marches; walk mid-chain → **total silence, chain gone** (verify in Diagnostics/audit); accessible
  alternative mid-chain → same; 30-min bound → silence after last entry; locked alarm's delete/disable
  rejected with the copy; power-cycle mid-chain → remaining entries still fire.
- **Audit:** every chain schedule/cancel and every lock rejection is an append-only audit event (#46–50).

## 8. Honest limitations (shipped copy + docs must not overclaim)

Power-off/dead battery = no ring while off (chain resumes on power-on for entries still in the future).
Uninstall = full escape (deterred honestly, never falsely). Full data reset = deliberate escape.
Accessible alternative = deliberate non-walk exit (required). Copy rule: **no duration claims in either
direction** — never "for 30 minutes" (confidential bound), never "forever/until you walk" (an over-claim a
user might rely on). The shippable phrasing: *"keeps re-ringing if you stop without completing the walk."*

## 9. Immediate next inputs

1. **The WG-287 calibration readings** (user): DEBUG pill after a ~10 s real walk and after a ~10 s shake —
   `int N/8 · CoV · s/step · verdict` for each. Blocks everything.
2. AlarmKit alarm-cap probe result (falls out of WG-291 on device).
