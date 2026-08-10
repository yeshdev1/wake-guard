# Wellness Data-Minimization Plan (WG-120)

WakeGuard's circadian intelligence reads a **minimal** slice of HealthKit, processes it **on-device
only**, and keeps **no raw samples**. This plan is the single, enforceable source of truth for *what*
is requested, *why*, *how long* it is kept, and *where* it is processed. It is backed by a typed registry
— `WellnessDataMinimizationPlan.mvp` (`Sources/HealthDomain/WellnessDataMinimizationPlan.swift`) — so the
guarantees below are not just prose: contextual authorization (WG-121) requests **exactly** the types in
that registry, and several rules are made *structurally impossible* to violate (see "Structural
guarantees"). Invariants referenced: `SAFETY_INVARIANTS.md` #34–#45, `PRODUCT_SPEC.md` §3.5 / non-goals.

## Requested types, purposes, retention, processing

| HealthKit type | Access | User-facing purpose | Raw retention | Processing | Cloud |
|---|---|---|---|---|---|
| Sleep analysis (`HKCategoryType(.sleepAnalysis)`) | **Read only** | "Estimate your recent sleep duration and consistency to explain your morning readiness. This is a sleep estimate, never a diagnosis." | **Compute-and-discard** (no raw samples kept) | **On-device only** | **Excluded** |

That is the **entire** set. WakeGuard's readiness explanation (WG-125) is derived from this sleep data
via transparent formulas (WG-123/124) — **not** from heart rate, HRV, workouts, or any other type — so
nothing else is requested. The app never *writes* to HealthKit.

## Retention and local processing

- **Raw samples: compute-and-discard.** Sleep samples are read to compute a derived estimate and then
  dropped — they are never persisted. Only coarse **derived aggregates** (e.g. estimated sleep duration /
  consistency for a day) may be stored.
- **Explicit, configurable retention (#43).** Derived aggregates are retained only as long as useful and
  are covered by the user's **export and delete controls** (WG-129, #42). A delete removes the stored
  aggregates; there is no raw HealthKit copy to remove because none is kept.
- **On-device only (#35).** All processing — querying, mapping, duration/consistency/debt/readiness — runs
  on the device. No wellness data leaves it.

## Cloud exclusion (explicit)

Raw HealthKit data is **never** sent to a cloud model or stored in the cloud by default (#35;
`PRODUCT_SPEC.md` non-goal: "Cloud storage of raw HealthKit … data"). The MVP is on-device only (ADR-004).
If a cloud wellness feature is ever offered it is a **separate, explicit opt-in consent** (#34) and would
require its own entry and review here — it can never be enabled implicitly by this plan.

## Optional and functional-without

Health features are **optional** (#36); permission is requested **in context** at the moment of use
(#37, WG-121); and the app remains fully useful — alarms and travel detection unaffected — when health
access is **denied or partial** (#38). Denied access yields an *unavailable* readiness state, never a
fabricated one (WG-123).

## Structural guarantees (enforced by the type system, not just docs)

The registry makes the most important rules impossible to violate at a call site:

- **No cloud processing.** `ProcessingLocality` has the single case `onDeviceOnly` — a cloud locality
  cannot be constructed, so an entry sending data off-device is unrepresentable (test:
  `testCloudProcessingIsStructurallyInexpressible`).
- **No writes.** `WellnessAccessMode` has the single case `read`.
- **No raw retention.** `WellnessRetention` has the single case `computeAndDiscard`.
- **Every type is justified.** Each entry carries a non-empty `userFacingPurpose`; authorization requests
  only `plan.requestedTypes` (test: `WellnessDataMinimizationPlanTests`).
- **No medical claim (#39).** Purposes are framed as *estimates* with an explicit "never a diagnosis"
  disclaimer; a test scans for claim language.

## Change process

Adding a HealthKit type is a deliberate change: add a `WellnessDataMinimizationEntry` (type + purpose +
retention + on-device processing), update this document, and — because it widens data collection — surface
fresh in-context consent (#37) and a privacy review. Never request a type ad hoc at a call site.

See also: `THREAT_MODEL.md` (privacy leakage), `RELEASE_CHECKLIST.md` (privacy section), and the export/
delete controls (WG-129).
