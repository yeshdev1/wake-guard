---
name: run-task
description: Implement one WakeGuard backlog task with tests, safety checks, and status updates.
argument-hint: <TASK_ID>
disable-model-invocation: true
---
Read `CLAUDE.md`, `docs/SAFETY_INVARIANTS.md`, `docs/DECISIONS.md`, and task `$ARGUMENTS` in `docs/BACKLOG.md`.

Classify the task's **risk tier** first — it sets review depth and pace:

- **Safety-critical** — touches alarm scheduling / policy / reconciliation, criticality, AI or agent output, persistence / audit / outbox, notifications, permissions, or time-zone / DST behavior, or any `SAFETY_INVARIANTS` rule. When unsure, treat it as this.
- **Low-risk** — pure test harness, docs / checklists, tooling / CI, or a change that cannot affect a safety invariant.

Workflow:

1. Confirm dependencies are Complete in `docs/IMPLEMENTATION_STATUS.md`; inspect the relevant files and tests; state a short plan.
2. Add or update a failing test where practical, then implement **only** the selected task.
3. **Gate with one build:** run `make ci-fast` and read its output. Use `make test-fast ONLY=<Suite>/<Case>` for quick feedback *only while a test is still failing* — do **not** run a separate narrow build and then a full build; one green `ci-fast` is the local gate (its checks match remote CI). Run `make format` after a large rewrite. Keep DerivedData warm (never `make clean` between tasks); run `make generate` only when `project.yml` changed or a source file was added/removed.
4. Prepare the docs: `docs/IMPLEMENTATION_STATUS.md` (status → Complete + a concise evidence row), a **tight** ADR in `docs/DECISIONS.md` only for a genuine decision (no filler), and the manual real-device checklist when the task changes alarm / motion / time-zone / notification behavior.
5. Commit the task as its own commit (code + docs).
6. **Review, scaled to risk:**
   - Safety-critical → launch the most relevant adversarial reviewer subagent(s) (`alarm-safety-reviewer`, `ios-architect`, `privacy-security-reviewer`, `motion-red-team`, `ux-accessibility-reviewer`, …), scoped to the changed files, with concrete claims-to-refute (Opus for the safety reviewer). **While they run, draft the completion report** to overlap the wait. Apply valid findings before pushing (amend or a follow-up commit); record deferred ones in `docs/DECISIONS.md`.
   - Low-risk → skip the subagent (or one quick pass, Sonnet, only if the change touches shared code).
7. **Push, then keep moving — do not watch CI synchronously.** `make ci-fast` matches remote CI (WG-005, no drift), so `git push HEAD:main` and continue; surface the CI result when it lands and only stop to fix if it goes red.
8. Report: task ID, files changed, exact test results, assumptions, risks, next unblocked task.

Never weaken an invariant or silently broaden scope. Rigor scales with risk, but the safety gate — deterministic tests plus adversarial review on any diff that can touch an invariant — is never skipped.
