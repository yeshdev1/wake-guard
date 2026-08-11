# Epoch 12 (WG-251): Release-candidate bug bash

A cross-cutting `release-test-engineer` sweep over the eleven dimension reviews (E01–E11): hunt for bugs that
only appear where subsystems **interact**, and confirm the E13 fixes are coherent (no fix regressed another
area). Plus the consolidated RC readiness register.

**Headline: the E13 fixes compose without conflict — no P0/P1, no regressions.** Specifically verified: the
WG-244 reconcile re-validation, the WG-242 `Etc/GMT±` rejection, and the WG-243 corroboration gate do not
share a construction site or contradict each other; the #1/#2 adapter boundary holds in the real
`AppEnvironment` graph; `ReconciliationSummary.stale` / `observedProgress` corroboration left every switch
exhaustive with no persisted-DTO back-compat surface; determinism/Sendable clean (no `Date()`/`UUID()` in a
domain path). Three P2/P3 findings — all on E13-authored code — fixed here.

## Fixed

- **P2 — diagnostics omitted `stale`/`skipped`.** `DiagnosticsRenderer.report` rendered only
  scheduled/cancelled/failed/uncertain, dropping WG-244's `stale` and, worse, `skipped` — the #10 fail-safe
  signal (ground truth/desired unreadable → nothing repaired). Now both are surfaced, with `skipped` flagged
  distinctly ("skipped: ground truth unreadable") so support can't mistake it for a healthy no-op. Pin:
  `DiagnosticsTests.testReportSurfacesStaleAndSkippedReconcileState`. (Latent — the provider is unwired until
  E14 — but now correct on day one when wired.)
- **P2 — WG-244 re-validation failed *open* on a read error.** `currentDesiredSchedule` used `try?`, so a
  transient `alarm(id:)` store failure returned `nil`, and the `.cancel` guard (`current == nil`) then
  *proceeded* — cancelling on unknown state, unlike the fail-*closed* posture everywhere else in the
  processor. Made it `throws`; `apply` now catches and **defers** the repair (counts `stale`, applies
  nothing) on a read failure. Pin: `AlarmReconciliationTests.testCancelRepairIsDeferredWhenTheRevalidationReadFails`.
- **P3 — `MovementCorroboration` doc contradicted the code.** The `.unavailable` doc-comment said a
  sensor-poor walker "still passes on the count (degraded)" — the pre-WG-243 behavior and the exact opposite
  of the machine (which accumulates but never passes on count alone). A maintainer trusting it could reopen
  the #20 shake hole. Corrected the comment to match the fail-safe code + test.

## Consolidated RC readiness

**The deterministic core is RC-quality and regression-locked** (1208 tests, 0 failures, 0 warnings): the
alarm-authority chain (#1–#7), scheduling/DST/travel math (#11–#17), the anti-shake challenge gate
(#18–#24), the AI advisory boundary (#26–#35), and privacy/audit (#36–#50) are each enforced *and* pinned,
with the E13 epochs adding lost-update, injection-carrier, prompt-redaction, accessibility, aesthetic,
perf/battery, and compliance locks.

**NOT shippable yet** — the outstanding blockers are all **composition wiring (E14)** and **device
verification**, none a defect in the logic that exists:

- **E14 composition (the dominant gap).** Built + unit-tested but not composed into `AppEnvironment`/`RootView`:
  the live challenge ring-stop (#18–#24 inert), `SystemTimeZoneMonitor` (background zone change corrected only
  on next foreground), the diagnostics provider, and — the **App Store submission blockers (WG-250)** — the
  `DataEraser`/retention runner + export/deletion/consent/conversational screens (privacy-label/behavior
  mismatch). Also the live pedometer/location/`BGTaskScheduler` adapters. Pinned by the WG-250 expected-failure
  gate + recorded across E03/E05/E11.
- **Device verification (WG-030).** AlarmKit ring-through-silent/Focus, critical-confirm, and absolute
  battery/latency budgets require on-device evidence (simulator is insufficient).
- **Tracked residuals (P2, non-gating).** Reconcile repairs bypass the outbox (revision-keyed idempotency
  would fully close the narrow in-flight race, E05); best-effort audit `try?` (#46); dead `.recovery`/outbox
  recovery API (#50); `Sensitive` adopted only for the cloud token (#181/E07).

## Method note

This bash is a synthesis of the eleven dimension reviews plus one fresh cross-cutting adversarial pass, not a
re-run of each dimension. The known E14/device items above were confirmed still-tracked, not re-litigated.
Final full-suite regression is WG-252.
