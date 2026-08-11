# Epoch 5 (WG-244): Background, reboot, permission & race chaos

An `alarm-safety-reviewer` pass adversarially attacked the lifecycle for any path that could **silently
suppress an alarm** or leave uncertain state unreconciled — kill/relaunch, reboot, permission revocation
mid-flight, background-task expiration, duplicate callbacks, out-of-order events — building on WG-226
(concurrency), WG-227 (corruption), and WG-229 (expiration/termination).

**Verdict: one real P1 (fixed), plus the standing composition-wiring gap (tracked → E14). No P0.**

## Fixed — P1: reconcile lost-update could silently drop a ring

`reconcile()` computed a repair plan from a one-shot snapshot, then applied each repair across `await`
points. `AlarmCommandProcessor` is a reentrant actor, so a queued `process(.enable/.disable/.delete)` runs
to completion at any suspension point — and the reconcile repairs went **straight to the adapter, bypassing
the outbox idempotency**. The dangerous interleaving:

1. Local alarm A is disabled but the system still holds it (a prior uncertain cancel, or a reboot where
   AlarmKit persisted it). Reconcile plans `.cancel(A)`.
2. During an earlier repair's `await` (or the `scheduledAlarms()`/`allAlarms()` reads), the user re-enables
   A: `process(.enable(A))` saves A enabled **and schedules it** in the system.
3. Reconcile resumes and applies the now-stale `.cancel(A)`. Net: local state says A is enabled, but the
   system alarm is gone — **A does not ring** until the next foreground reconcile (which may be after the
   fire time). A silent suppression under normal operation — the only such path found.

**Fix (`AlarmCommandProcessor.apply(_:into:)` + `currentDesiredSchedule`):** every repair is re-validated
against **freshly-read desired state on the actor immediately before the adapter call**. A `.cancel` whose
alarm is now enabled-with-an-occurrence is dropped (`summary.stale`); a `.schedule` whose alarm is now
absent/disabled, or whose fire time no longer matches the current desired occurrence, is dropped. The
command path already synced the current intent, so a fresh pass converges (#10). A genuinely-needed repair
re-validates identically (same engine/now/zone as the planner) and still applies, so normal reconciliation
is unchanged.

**Residual (documented, not silently ignored):** a mutation landing *during the single repair's own adapter
`await*`, after the re-read, is a much narrower window whose outcome depends on the adapter serializing its
own calls (the real AlarmKit adapter serializes on the manager). Full closure would route reconcile repairs
through the same revision-keyed outbox as commands — tracked for the composition/hardening epoch.

**Regression tests** (`AlarmReconciliationTests`): `testStaleCancelIsSkippedWhenAConcurrentEnableRestoredTheAlarm`
(the exploit: a stale cancel must not drop the re-enabled alarm) and
`testStaleScheduleIsSkippedWhenAConcurrentDisableRemovedTheAlarm` (the mirror: a stale schedule must not
resurrect a cleared alarm). Both drive the lost-update window deterministically via an
`InterleavingAlarmRepository` that reports the plan-time enable state once, then the flipped state on every
apply-time re-read — no real thread race needed.

## Confirmed safe (no gap)

- **Kill/relaunch + reboot.** AlarmKit persists `.fixed` alarms and rings them without the app; on relaunch
  `AlarmListView` (`.task` + `scenePhase == .active`, the always-mounted root) triggers the idempotent,
  fail-safe `reconcile()`. Covered by `CorruptionRecoveryTests`, `AlarmReconciliationTests`.
- **Permission revocation mid-flight.** `scheduleFixed` throws `.notAuthorized` → mapped to `.uncertain`,
  local desired state preserved; the permission banner refreshes every foreground. Never a silent drop.
- **BG task expiration.** `PreAlarmBackgroundRunner` reschedules first, wires expiration→cancel race-free,
  holds no alarm authority (#9). Covered by `BackgroundExpirationTerminationTests`.
- **Duplicate callbacks.** Challenge pass dedups via the `ChallengeStopCoordinator` actor + `stopRing`
  outbox key; duplicate `keepOriginal`/`cancelOccurrence` are idempotent no-ops; corrupt payloads decode
  fail-closed.
- **Uncertain outcomes.** Every adapter `.uncertain`/cancellation is audited honestly as `.failed`/not-
  "stopped", local state persisted first, and re-checked against ground truth on the next pass.

## Tracked → E14 (composition/wiring), not defects in existing logic

The reviewer re-surfaced the standing gap: several subsystems are built + unit-tested but **not yet wired
into the composition root**, so their guarantees are latent. These are scheduled for the integration epoch,
not this review task (recorded here so "component-tested" is not mistaken for "reachable end-to-end"):

- **Challenge stop** (`ChallengeStopCoordinator`/`ChallengeView`) is not presented on alarm fire — the live
  ring is stopped by AlarmKit's native Stop, so the walk-verification (#18–#24) is not yet end-to-end.
- **Time-zone monitor** (`SystemTimeZoneMonitor`) is never started — a background zone change is corrected
  only on the next foreground reconcile, not live (#12–#14).
- **Diagnostics** (WG-230) has no production provider — `reconcile()`'s `.failed`/`.uncertain` summary is
  discarded at the call site, so there is no support-visible sync signal.
- **Outbox recovery API** (`unresolvedEntries()`) has no production consumer — ground-truth reconciliation
  supersedes it, and non-terminal entries are not reaped (unbounded growth; see also Epoch 1 P2).

See `docs/DECISIONS.md` (WG-244) for the E14 disposition.
