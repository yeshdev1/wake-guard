# Performance budgets & baselines (WG-222)

Budgets the app is held to, and the paths measured. Structural bounds are pinned by `PerformanceTests`;
device-level numbers are captured on the measurement matrix.

## Budgets

| Path | Budget | Notes |
|---|---|---|
| Cold launch to interactive | ≤ 400 ms (p50), ≤ 800 ms (p95) | On the minimum device (iPhone SE 3rd gen). |
| Launch reconciliation (read desired state, compute next-fire, diff) | ≤ 250 ms for 1,000 alarms | Never blocks the first frame; runs after launch and on foreground. Opportunistic (#10). |
| Next-occurrence calc (hot path) | ≤ 50 µs / call | Pure `AlarmSchedulingEngine.nextOccurrence`; called per alarm during reconciliation. |

## Large histories

Reconciliation cost is **linear** in the alarm count. `PerformanceTests` computes next-fire times for a
large alarm set (2,000 rules) and asserts it completes well within a CI-safe bound, so a big history can't
make launch pathological. Audit history is bounded by retention (WG-182) and paged, never fully loaded to
schedule.

## Slow-path profiling

- **Time-zone / DST resolution** in `nextOccurrence` (Calendar work) is the dominant per-call cost —
  measured via `measure {}` so a regression shows up as a baseline delta.
- **Core Data reads** are batched and read-only on the launch path; the schedule computation is pure and
  off the store.

## Measurement conditions

Numbers are captured on the minimum device, warm and cold, airplane mode off, default Focus, battery > 50%.
Regressions are triaged against the checked-in baseline.
