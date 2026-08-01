# Safety Invariants

These invariants override feature convenience.

## Alarm authority

1. `AlarmManagerAdapter` is the only component that calls AlarmKit.
2. Only `AlarmCommandProcessor` can invoke the adapter.
3. Every command must be authorized by `AlarmPolicyEngine`.
4. LLM components can produce only `AlarmProposal` values.
5. An `AlarmProposal` is never executable without validation and policy authorization.
6. Critical alarms cannot be cancelled, delayed, or weakened without explicit user confirmation.
7. No response to a prompt means no mutation.
8. Movement-based “likely awake” inference never cancels an alarm in the MVP.
9. A background task is never required for an alarm to ring.
10. An app crash, task expiration, model failure, permission denial, sensor gap, or network failure must preserve the last known safe scheduled alarm.

## Time and travel

11. Store IANA time-zone identifiers.
12. Distinguish wall-clock recurring intent from fixed instant intent.
13. Recompute schedules after time-zone or calendar changes through a pure scheduling engine.
14. Detect ambiguous and nonexistent local times around DST.
15. Crossing the International Date Line must not duplicate or skip an alarm without an explicit schedule rule.
16. Location may suggest context but cannot silently change a critical schedule.
17. Cached location must be timestamp-validated.

## Wake verification

18. A challenge starts only after explicit user interaction.
19. A pass requires multiple independent signals when available.
20. Shaking alone cannot pass.
21. Sensor unavailability cannot trap the user indefinitely.
22. Provide an accessible alternative.
23. Challenge state must survive ordinary UI transitions.
24. The alarm stop command is issued only after the challenge state machine reaches a valid terminal pass or the user uses an authorized fallback.
25. The app must disclose that carrying the phone is necessary.

## AI

26. Use constrained structured outputs.
27. Reject unknown enum values, out-of-range times, invalid dates, and unrecognized alarm IDs.
28. Treat calendar titles, journal text, and imported content as untrusted prompt content.
29. Never allow untrusted content to override system policies or tool permissions.
30. Do not expose a general-purpose tool that accepts arbitrary alarm mutations.
31. The policy engine, not the model, assigns criticality and authorization.
32. AI explanations must be derived from recorded factors, not invented reasons.
33. If model availability or confidence is inadequate, fall back to deterministic UI.
34. Cloud processing is opt-in and separately consented.
35. Do not send raw HealthKit, precise location, or full calendar text to a cloud model by default.

## Health and privacy

36. Health features remain optional.
37. Request each permission in context.
38. The app remains useful with optional permissions denied.
39. Do not make medical claims.
40. Do not use health, motion, location, or calendar data for advertising.
41. Do not log sensitive raw values.
42. Provide export and deletion controls.
43. Retention periods are explicit and configurable where appropriate.
44. Analytics use coarse, non-sensitive events.
45. Every third-party SDK requires a privacy review.

## Auditability

46. Every alarm mutation records actor: user, system reconciliation, approved agent proposal, migration, or recovery.
47. Record old and new state, reason, timestamp, correlation ID, and outcome.
48. Audit records are append-only in normal operation.
49. Display a user-understandable history.
50. Recovery actions are distinguishable from ordinary edits.
