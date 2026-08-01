---
name: run-task
description: Implement one WakeGuard backlog task with tests, safety checks, and status updates.
argument-hint: <TASK_ID>
disable-model-invocation: true
---
Read `CLAUDE.md`, `docs/SAFETY_INVARIANTS.md`, `docs/DECISIONS.md`, and task `$ARGUMENTS` in `docs/BACKLOG.md`.

Workflow:

1. Confirm dependencies are complete in `docs/IMPLEMENTATION_STATUS.md`.
2. Inspect relevant files and tests.
3. State a short plan.
4. Add or update a failing test where practical.
5. Implement only the selected task.
6. Run narrow tests.
7. Run the full available suite.
8. Run formatter/linter.
9. Ask the most relevant custom reviewer subagent to inspect the diff.
10. Fix valid findings.
11. Update status, decisions, and manual test checklist.
12. Report changed files, exact test results, assumptions, risks, and next unblocked task.

Never weaken an invariant or silently broaden scope.
