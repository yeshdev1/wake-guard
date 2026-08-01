---
name: release-gate
description: Evaluate the exact WakeGuard release candidate against all release requirements.
disable-model-invocation: true
---
Read `docs/RELEASE_CHECKLIST.md`, all review reports, implementation status, and safety invariants.

Do not change code initially.

1. Record commit SHA, build number, toolchain, target devices, and feature flags.
2. Verify every checklist item has evidence.
3. Run all available automated checks.
4. Ask alarm-safety, privacy-security, ux-accessibility, and release-test subagents for independent reports.
5. Mark unsupported claims as Not Verified, never Passed.
6. Produce `docs/reviews/<date>-release-gate.md`.
7. Return a clear SHIP or DO NOT SHIP recommendation with blockers.
