# WakeGuard — Ring → Challenge → Re-arm Plan (enforced walk challenge)

Status: **proposed — awaiting sign-off**. Goal: a fired alarm reliably rings (AlarmKit), **opens the app into
the walk challenge**, and **re-arms if the challenge isn't passed** — so the walk is *effectively* enforced,
within AlarmKit's constraints. Belongs on `main` (not the free-account test branch). No code yet.

> **Platform ceiling (design premise):** AlarmKit *requires* a Stop button on every system alarm — iOS
> guarantees a user can stop a ringing alarm, and that cannot be removed. So enforcement is **re-arm**
> (it keeps coming back until you walk), **not a lock**. Reliable ring + effectively-forced challenge; the
> system Stop stays as an escape hatch that the re-arm loop makes pointless.

---

## 1. What already exists (reuse — do not rebuild)

- **WG-073 (Complete) — the "pass → stop" half.** `WakeChallengeRuntime` (live pedometer → anti-shake
  machine → **authorized** stop), `ChallengeHostView`, and the accessible tap/hold fallback (#21/#22). When
  the machine reaches `.passed`, it already calls the processor's authorized stop. **We reuse this whole
  runtime unchanged** — it just needs to be *presented on a real ring* instead of only the in-app "Test
  challenge" rehearsal.
- **`SystemAlarmManagerAdapter`** — schedules a `.fixed` AlarmKit alarm; has `stopRing`, `cancel`,
  `scheduledAlarms`. Today the alarm carries only a plain **Stop** button.

**The three gaps to close:**
1. The alarm has no button that **opens the app** → the challenge is never shown on a real ring.
2. No **launch routing** from a ringing alarm to the challenge for that alarm.
3. No **re-arm** when the challenge isn't passed.

---

## 2. Guardrails (safety — this is a safety-sensitive change)

- **Never trap a user (#21/#22).** The accessible fallback must be reachable from *every* ring; a pedometer
  that's unavailable/denied/ambiguous presents the accessible alternative, never a dead end (existing
  invariant — the runtime already does this).
- **Bounded + cancellable (needs an ADR + human approval).** An alarm a user *cannot* end is abuse and a
  safety risk (emergencies). The re-arm loop must have a cap and the alarm must always be cancellable via the
  normal path (a critical alarm → cancel-confirmation #6, but still possible). This is the one place we
  *change* alarm-dismissal behavior, so it lands behind a `DECISIONS.md` ADR.
- **Pass is an explicit action, not an inference (#8).** Stopping requires a genuine walk (or the accessible
  action) — movement inference alone never stops it. WG-073's anti-shake gate already enforces this.
- **Everything audited + policy-gated.** Every re-arm and stop is an append-only audit event
  (actor/reason/old→new). All scheduling mutations route through `AlarmCommandProcessor` /
  `AlarmPolicyEngine` — no new component calls `AlarmManager` except the existing adapter (#1).
- **Reconciliation stays coherent (#10).** A re-armed alarm is *desired* system state; `AlarmReconciler`
  (WG-029) must track it and not fight the loop.

---

## 3. Phases (proposed WG-280 … WG-286)

### WG-280 — Spike: AlarmKit "open the app on tap" (device research, no shipping code)
- Determine the exact iOS-26 AlarmKit mechanism to make a **fired alarm launch the app carrying the alarm
  ID**, without stopping the ring: an App-Intent-backed secondary `AlarmButton`, the alert's open-app
  behavior, or a deep link. AlarmKit is new — confirm on-device which delivers the alarm ID to a cold app.
- **Output:** the chosen mechanism + a minimal proof on a device. Gates the rest.

### WG-281 — Alarm carries a "Start walk" wake action (adapter)
- Extend `SystemAlarmManagerAdapter.scheduleFixed` to add a **secondary button** (from WG-280) that **opens
  the app without stopping**, tagged with the alarm ID. Keep the mandatory **Stop** (the escape hatch).
- Only add the wake action when the alarm **has a challenge** (thread a `hasChallenge`/`requiredSteps` flag
  through `AlarmScheduleRequest`).
- **Acceptance:** device — a challenge alarm rings with **Stop + Start walk**; Start walk opens the app, ring
  continues; Stop still stops. Coarse-redacted errors preserved (#41).

### WG-282 — Launch routing: ring → present the challenge for that alarm
- Add a **challenge route** (App Intent handler and/or `wakeguard://challenge/<uuid>`) that, on open,
  presents `ChallengeHostView` **full-screen** for that alarm ID — reusing WG-073's runtime verbatim.
- Handle cold-launch vs already-running; ignore an unknown/again-tapped id (fail-safe, like the existing
  deep-link parser — a link only *opens a screen*, never mutates).
- On pass → WG-073's authorized stop fires (no change). Accessible fallback reachable here.
- **Acceptance:** device — tapping Start walk opens straight into the walk challenge; a real walk stops the
  ring exactly once; the accessible alternative also stops it.

### WG-283 — Domain: pending-challenge + re-arm policy (pure, unit-tested)
- `PendingChallenge` (alarmID, originalFireTime, attempts) + a **pure** `RearmPolicy`:
  `next(now, pending, config) -> .rearm(at: Date) | .stop`. **Bounded** — e.g. re-arm every *interval* up to
  *maxAttempts* / *maxWindow*, then `.stop` (safe give-up). Deterministic; injected `Clock`.
- **Acceptance:** unit tests — re-arms at the interval, stops at the cap, never unbounded; a passed challenge
  yields no re-arm.

### WG-284 — Wire the re-arm loop (application, policy-gated + audited)
- Persist `PendingChallenge` when a challenge alarm fires; **clear it on a pass**.
- **Re-arm trigger:** on app foreground (or AlarmKit alerting-ended observation), if a pending challenge's
  alarm is past its fire time and **no pass was recorded** → the user stopped it without walking → schedule
  the follow-up via the **command processor** (`RearmPolicy` → `.create/.schedule`), audited
  (`.systemReconciliation`-style actor), until the cap.
- Reconcile (WG-029) treats the re-armed alarm as desired state.
- **Acceptance:** integration (real in-memory Core Data) — pass → cleared, no re-arm; stop-without-pass →
  one re-armed alarm + audit; cap reached → stops; reconcile doesn't cancel the re-arm.

### WG-285 — Safety, accessibility, edge cases + the ADR
- `DECISIONS.md` ADR for the **bounded re-arm** (the dismissal-behavior change) + **human approval**.
- Pedometer denied/unavailable → accessible fallback presented (fail-safe). Never a trap.
- Battery: re-arm uses AlarmKit (system-scheduled), not background execution (#9) — cheap; bound the live
  pedometer session lifetime; cancel cleanly.
- A user can always end it (normal cancel path; critical → #6 confirm).
- **Acceptance:** the invariant pins stay green; new tests for the fail-safe + cap + cancel paths.

### WG-286 — Device matrix + docs
- `DEVICE_SMOKE_TEST.md` cases: ring → Start walk → walk → stops; ring → **Stop, don't walk → re-arms** ~2 min
  later; accessible fallback stops; **cap reached → stops**; ring through silent + Focus each cycle.
- Update `TESTABILITY_REPORT.md` (this closes the "unattended ring → challenge" device-only gap) +
  `IMPLEMENTATION_STATUS.md`.

---

## 4. End-to-end flow (target)

```
alarm fires (AlarmKit, rings through silent/Focus)
   │  shows: [Stop]  [Start walk →opens app]
   ├─ user taps Start walk ──► app opens ──► ChallengeHostView (WG-073 runtime)
   │       ├─ walks / does accessible action ──► PASS ──► authorized stop ──► clear pending ✔ done
   │       └─ leaves without passing ─────────────┐
   └─ user taps Stop (no walk) ───────────────────┤
                                                   ▼
                            on foreground / alerting-ended: pending unsatisfied?
                                   └─ RearmPolicy → re-arm ~2 min out (audited, capped)
                                          └─ rings again … loop until PASS or cap
```

## 5. Decisions (locked 2026-08-12)
1. **Re-arm cadence** — every **2 minutes**, up to **15 cycles (~30 min)**, then stop (the safety cap).
2. **Scope** — **critical alarms only.** Standard alarms keep the plain Stop, no re-arm.
3. **Button label** — **"Start walk."**
4. **Trigger** — re-arm **only on a confirmed stop-without-pass.** Backgrounding the app mid-challenge does
   **not** re-arm (a user glancing at a text mid-walk isn't punished).
