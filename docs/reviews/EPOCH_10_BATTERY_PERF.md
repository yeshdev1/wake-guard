# Epoch 10 (WG-249): Battery & performance regression

A `release-test-engineer` pass verified the six power/perf constraints hold in source and that the four
pinned suites (`PerformanceTests`, `BatteryBaselineTests`, `MotionChallengeSensorTests`,
`BackgroundSchedulingTests`) are green.

**Verdict: PASS.** All constraints hold; the two gaps were missing regression *locks* (the good behavior is
present but was under-pinned), both added here. Absolute drain / latency remain a device-matrix manual pass.

## Fixed — added the missing locks

- **Gap A — hot-path had no gating perf bound.** `testNextOccurrenceHotPathBaseline` uses `measure {}` but no
  `.xcbaseline` is checked in, so it records without gating — a gross per-call regression (e.g. an accidental
  O(n) scan in the DST/Calendar path) would pass. Added
  `testNextOccurrenceHotPathStaysWithinAFunctionalBound`: 10,000 `nextOccurrence` computations must finish
  under a generous wall bound (`ContinuousClock`, observed ~0.77s ≪ 2s), gating independently of Xcode
  baselines — mirroring the existing large-history test.
- **Gap B — "HealthKit not continuously observed" was unpinned.** Location's continuous-drain APIs are
  scan-asserted absent, but the analogous HealthKit continuous-observation APIs were not. Added
  `testHealthKitIsNotContinuouslyObserved`: scans `HealthInfrastructure` and asserts `HKObserverQuery`,
  `HKAnchoredObjectQuery`, `enableBackgroundDelivery` are absent and that on-demand `HKSampleQuery` is used —
  so a future change turning nightly sleep reads into a real-time trigger (violating the core constraint and
  the +health budget) fails CI.

## Confirmed (enforcement → pin)

- **No continuous GPS.** Only `startMonitoringSignificantLocationChanges`; the continuous-drain APIs are
  scan-absent; only a coarse timestamp is stored, never coordinates. Pins: `BatteryBaselineTests`,
  `BackgroundSchedulingTests`.
- **Motion sensors bounded.** `CMPedometer` (cumulative) only; each live stream pairs `start` with an
  `onTermination` stop; raw high-Hz inertial APIs (`CMMotionManager`, accelerometer/gyro/deviceMotion) are
  scan-absent. Pin: `MotionChallengeSensorTests`.
- **HealthKit on demand.** One-shot `HKSampleQuery` over a bounded window, cancelable; never a wake trigger.
  Now pinned (Gap B).
- **Background opportunistic.** `PreAlarmBackgroundRunner` reschedules-first, wires expiration→cancel
  race-free, holds no alarm authority (#9); no wakelock/busy-wait/`Task.sleep`; reschedule interval clamped
  ≥60s. Pins: `BackgroundSchedulingTests`.
- **Scheduling perf.** `earliestWeekly` iterates ≤7 weekdays × fixed week-offsets — constant-cost, pure, no
  O(n²)/unbounded loop. Pins: `PerformanceTests` (large-history bound + the new per-call bound).
- **No unbounded retries / timers.** Outbox `maxAttempts = 5` enforced; no `Timer` anywhere (so no missing
  `.invalidate()`); no polling sleeps.

## E14 (not-yet-wired — called out, not gated as defects)

The live walk-challenge pedometer (`CoreMotionLivePedometerAdapter`), the motion-activity adapter, the
significant-location adapter, `SystemTimeZoneMonitor`, and the real `BGTaskScheduler` registration are
implemented + scan-pinned but not yet composed into `AppEnvironment`. The low-power *design* is locked by the
scans above, so wiring them later cannot silently introduce continuous sensing without failing CI.

## Manual verification still required (device matrix — not produced here)

Absolute overnight drain vs `docs/BATTERY.md` budgets (alarms ≤1%; +location ≤0.5%; +health ≤0.3%; +pre-alarm
≤0.5%); step→pass latency (≤250/500 ms) and pedometer-stops-after-pass via Energy Log; cold-launch p50/p95 on
iPhone SE (3rd gen). These are device scenarios and must not be marked passed on simulator evidence.
