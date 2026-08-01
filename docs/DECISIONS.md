# Architecture Decision Record Index

Record each decision as:

```text
## ADR-XXX: Title
Status:
Date:
Context:
Decision:
Alternatives considered:
Consequences:
Safety/privacy impact:
Revisit trigger:
```

Initial decisions to make:

- ADR-001: iOS 26+ minimum versus fallback support.
- ADR-002: SwiftData versus Core Data.
- ADR-003: single target versus local Swift packages.
- ADR-004: on-device-only MVP AI versus optional cloud provider.
- ADR-005: default ten-second walk thresholds.
- ADR-006: accessible challenge alternatives.
- ADR-007: critical alarm definition.
- ADR-008: pre-alarm evaluation windows.
- ADR-009: audit retention.
- ADR-010: analytics provider or no analytics.

## Assumptions log

Material assumptions recorded per `CLAUDE.md`. These are not ADRs; formal
decisions are recorded above using the ADR template.

### WG-001 (2026-08-01): Scope and terminology freeze

- MVP scope and shared vocabulary are frozen in a dedicated `docs/SCOPE.md`
  rather than inline in `PRODUCT_SPEC.md`, so scope/terminology change control
  has one authoritative home. `PRODUCT_SPEC.md` remains the product detail.
- The **operational** definition of "critical alarm" (which categories default
  to critical, snooze/challenge constraints, thresholds) is intentionally
  deferred to **ADR-007**, which is indexed in this file's ADR list but not yet
  scheduled to a task (WG-002 owns ADR-001/002/003/004 only). WG-001 fixes only
  the term and its non-negotiable safety semantics, to avoid pre-empting the ADR.
- No automated test suite exists yet (no Xcode/SwiftPM target until WG-003;
  test-support module is WG-007). WG-001 is a documentation-only change, so its
  acceptance is verified by inspection; the "full available suite" is currently
  empty (0 tests). No test harness was introduced here to avoid broadening scope
  into WG-003/WG-004/WG-005/WG-007.
- `SCOPE.md` was intentionally **not** added to the `CLAUDE.md` always-read list
  in this task (editing `CLAUDE.md` would broaden scope). Recommended as a small
  follow-up.
- **Stricter-than-source terminology (intentional).** `SCOPE.md` §2 deliberately
  strengthens a few source statements: the "critical alarm" entry adds the verb
  "suppressed" to invariant #6's prohibitions and bans AI *inference* of
  criticality (beyond #31's wording), and §4 broadens the advertising exclusion
  to match #40 (adds location + calendar). These tighten safety and never weaken
  an invariant, so no ADR is required; recorded here so the deviations are not
  silent.
- **`AlarmManagerAdapter` naming reconciliation (follow-up).** `SAFETY_INVARIANTS.md`
  #1–#2 name `AlarmManagerAdapter` as the sole AlarmKit caller, but
  `ARCHITECTURE.md` §4 does not list that identifier. `SCOPE.md` §2.5 now defines
  it; reconciling the name into `ARCHITECTURE.md` is left as a small follow-up
  (candidate: WG-002 or the alarm-infrastructure tasks WG-024/027/028).

### WG-001 adversarial review (2026-08-01)

- A 3-round, 6-lens multi-agent adversarial review (safety-conflict,
  internal-consistency, correctness-vs-source, completeness, exploitability
  red-team, quality/clarity) with 3-skeptic majority verification confirmed **no
  safety-invariant weakening** and surfaced **7 unique docs-accuracy defects**
  (wrong invariant citations on `AlarmProposal`/DST/wake-challenge; a dropped
  circadian-suggestion capability; undefined cloud-AI MVP status; an undefined
  §2 change-control gate; overstated glossary count). All were fixed in the same
  pass. Report: `docs/reviews/2026-08-01-wg001-scope-terminology.md`.
