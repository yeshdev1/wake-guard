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
  deferred to **ADR-007** under WG-002. WG-001 fixes only the term and its
  non-negotiable safety semantics, to avoid pre-empting the ADR task.
- No automated test suite exists yet (no Xcode/SwiftPM target until WG-003;
  test-support module is WG-007). WG-001 is a documentation-only change, so its
  acceptance is verified by inspection; the "full available suite" is currently
  empty (0 tests). No test harness was introduced here to avoid broadening scope
  into WG-003/WG-004/WG-005/WG-007.
- `SCOPE.md` was intentionally **not** added to the `CLAUDE.md` always-read list
  in this task (editing `CLAUDE.md` would broaden scope). Recommended as a small
  follow-up.
