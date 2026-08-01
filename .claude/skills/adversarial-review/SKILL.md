---
name: adversarial-review
description: Run a named WakeGuard stabilization epoch and produce a severity-ranked review report.
argument-hint: <epoch-name>
disable-model-invocation: true
---
Read `docs/REVIEW_EPOCHS.md`, `CLAUDE.md`, and `docs/SAFETY_INVARIANTS.md`.

For epoch `$ARGUMENTS`:

1. Record commit SHA and environment.
2. Choose at least two independent relevant subagents.
3. Generate attacks before examining existing tests.
4. Inspect and run code/tests.
5. Write `docs/reviews/<date>-<epoch>.md`.
6. For each finding include severity, reproduction, invariant, impact, fix, and regression test.
7. Do not fix findings in the same pass unless explicitly instructed.
8. End with a release-blocking summary.
