# Overnight battery baseline (WG-223)

The overnight drain budget and the low-power design that meets it. The continuous-sensing regressions that
would blow the budget are pinned by `BatteryBaselineTests`; absolute drain is captured on the device matrix.

## Budget

| Scenario | Overnight drain budget (8 h idle, screen off) |
|---|---|
| Alarms only (all optional features off) | ≤ 1% |
| + Location (time-zone travel detection) | ≤ +0.5% |
| + Health readiness (nightly query) | ≤ +0.3% |
| + Pre-alarm awake check | ≤ +0.5% (only in the pre-alarm window) |

## Features off vs on

The measurement suite records overnight drain with each optional feature **off** and **on**, so a
regression in any single feature is isolated. Expectations:

- **Location off vs on** — negligible delta: only `startMonitoringSignificantLocationChanges` (cell/Wi-Fi),
  **never** continuous GPS, so the radio isn't held awake.
- **Health off vs on** — a single bounded query, not continuous observation.
- **Motion** — the pedometer runs **only during the walk challenge** (a bounded, awake window), so it does
  **not** contribute to overnight idle drain (WG-224 tightens challenge sensing).

## Continuous-sensing regression detection

`BatteryBaselineTests` scans the sensing infrastructure for the APIs that cause continuous drain
(`startUpdatingLocation`, `allowsBackgroundLocationUpdates`, high `desiredAccuracy`, `startMonitoringVisits`)
and asserts they are **absent** — so a change that swaps low-power sensing for continuous sensing fails CI
before it ever reaches a battery run.

## Device conditions

Captured on the minimum device, ~50% start charge, airplane mode off, default Focus, no other foreground
app, over an 8-hour idle window. Regressions are triaged against the checked-in baseline.
