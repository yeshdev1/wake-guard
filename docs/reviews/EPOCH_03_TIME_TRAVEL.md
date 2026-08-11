# Epoch 3 (WG-242): Time / DST / recurrence / travel red team

An adversarial reviewer re-implemented the engine's day-resolution/classify logic standalone and
**brute-forced every IANA time zone 2020–2030** (the automated matrix), plus manual DST/date-line
simulations. The deterministic **math is very strong** — zero drops or mislandings across all zones for
spring-forward gaps, fall-back folds, date-line skips, month/year/leap boundaries, and week-wrap. Findings
are at the wiring/test boundary.

## Fixed this epoch

- **P2 (#11 gap) — `Etc/GMT±N` fixed-offset zones were accepted.** `Etc/GMT+5` is a non-zero, POSIX-inverted,
  **no-DST** offset zone — exactly what #11 forbids — yet it passed `IANATimeZone` (which only checked the
  `GMT±` canonical prefix) and a test even enshrined it. **Fixed:** reject `Etc/GMT+…`/`Etc/GMT-…` while
  keeping the legitimate zero-offset references (`UTC`, `Etc/UTC`, `Etc/GMT`, which canonicalize to `GMT`).
  Regression: `TimeRedTeamTests.testEtcGmtOffsetZonesAreRejected` + corrected `AlarmDomainTests`.

## Regression tests added

- **Fall-back anti-double-fire (#2).** DECISIONS flagged that any enumeration feeding the prior result
  forward could re-fire at the **repeated** fall-back instant. The engine already prevents this
  (day-anchored `.first` policy), but it was unpinned. `TimeRedTeamTests.testFallBackRepeatedHourDoesNotDoubleFire`
  pins it: a daily 01:30 America/New_York alarm asked at 06:00 UTC on 2026-11-01 (between the two 01:30s)
  advances to the next day, never the second 01:30.

## Verified HANDLED + TESTED (empirically)

Spring-forward gap (resolves to transition, never nil-drops — verified all zones); fall-back single-call
(earlier instant); date-line skip (`.skippedAcrossDateLine`, fires next existing day, never lost);
recurrence boundaries (month/year/Feb-29/week-wrap/daily); wall-clock vs fixed-instant intents;
fixed-offset `GMT±HHMM`/`UTC+5` rejection.

## Tracked blocking issues (not fixed here)

- **P1 — the travel / time-zone-change subsystem is UNWIRED into the app.** `SystemTimeZoneMonitor`,
  `TimeZoneChangePrompt`, `TravelPolicyEvaluator`, `RapidZoneChangeGate` (WG-100–108) are complete and
  unit-tested but referenced nowhere in `AppComposition`/`RootView`. The only zone-change response at
  runtime is the scene-phase `reconcile()` on the alarm-list screen, so the `askOnChange` prompt and the
  critical-shift confirmation never surface, and `RapidZoneChangeGate` is never consulted. Alarms stay
  correct (reconcile re-times them), but the travel UX is missing. **Owner: a composition task** (wire the
  monitor → detector → prompt → policy path into `AppEnvironment`/`RootView`) before enabling travel prompts.
- **Critical follow-local reconcile is explicit by design.** A device zone change silently re-times a
  *critical* follow-local alarm's absolute instant — this is **intended** (the user pre-chose "follow local",
  so their local wake time is preserved), not a #16 breach (#16 covers a *silent criticality change*, which
  the reconciler does surface). Documented here so the behaviour is explicit; a reconcile test with a
  non-`.gmt` device zone should pin it when travel is wired.
