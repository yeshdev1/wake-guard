# Code Review Rules

Reviewers must prioritize:

1. Silent alarm suppression or schedule corruption.
2. Policy bypass, especially AI-to-alarm paths.
3. Time-zone, DST, recurrence, and race errors.
4. Persistence/AlarmKit divergence.
5. Motion false positives and inaccessible challenge flows.
6. Sensitive data in logs, analytics, prompts, exports, or third parties.
7. Async cancellation, actor isolation, and duplicate callbacks.
8. Missing denied/revoked permission behavior.
9. User copy that hides the safe default.
10. Accessibility and visual regressions.

Every high-severity finding should include:

- exact file and line;
- reproduction or concrete execution path;
- violated invariant;
- user impact;
- proposed regression test;
- smallest safe fix.
