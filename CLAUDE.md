# Project Instructions for Claude Code

## Product context

WakeGuard is a safety-sensitive iOS alarm and circadian-wellness app. Its core is deterministic. AI is advisory and permission-gated.

## Always-read documents

Before implementation, read:

- `docs/PRODUCT_SPEC.md`
- `docs/ARCHITECTURE.md`
- `docs/SAFETY_INVARIANTS.md`
- the selected task in `docs/BACKLOG.md`
- `docs/DECISIONS.md`
- `docs/IMPLEMENTATION_STATUS.md`, if present

## Scope discipline

- Implement one backlog task at a time.
- Do not add features not required by the task.
- Do not perform broad refactors while implementing a feature.
- Record material assumptions in `docs/DECISIONS.md`.
- Mark task status only after tests and acceptance criteria pass.
- Never delete a failing test merely to obtain a green build.
- Never weaken a safety assertion without an explicit ADR and human approval.

## Architecture rules

- Use SwiftUI and Swift concurrency.
- Keep domain logic independent of Apple frameworks.
- Wrap AlarmKit, Core Motion, Core Location, HealthKit, EventKit, UserNotifications, persistence, and model providers behind protocols.
- Route all time reads through an injected `Clock` abstraction.
- Route all UUID generation through an injected identifier generator in deterministic tests.
- Make scheduling calculations pure wherever possible.
- Store IANA time-zone identifiers, not only numeric UTC offsets.
- Represent user-facing alarm changes as commands evaluated by a deterministic policy engine.
- Persist alarm state before and after external scheduling calls and reconcile on launch.
- Treat background execution as opportunistic. Never require a `BGTaskScheduler` run to preserve a critical alarm.
- Do not use continuous GPS for travel detection.
- Do not treat HealthKit sleep stages as real-time wake triggers.
- Prefer on-device processing and data minimization.

## Safety invariants

- AI cannot call AlarmKit directly.
- AI cannot mutate persistence directly.
- AI output must be decoded into constrained structured types.
- All proposed alarm mutations pass through `AlarmPolicyEngine`.
- Critical alarms require explicit user confirmation for cancellation or delay.
- No response to a pre-alarm prompt means the original alarm remains unchanged.
- A movement inference alone never suppresses an alarm in the MVP.
- A failed, unavailable, denied, interrupted, or ambiguous challenge keeps the alarm active and offers a safe fallback.
- Every mutation creates an append-only audit event with actor, reason, old state, new state, and timestamp.
- Never log raw health samples, precise location, calendar titles, user journal text, or LLM prompts containing sensitive data.
- Do not make diagnostic or treatment claims.

## Testing rules

For every task:

1. Add or update unit tests.
2. Add integration tests when crossing an adapter boundary.
3. Include denied-permission and unavailable-hardware behavior where relevant.
4. Include cancellation and concurrency behavior for async code.
5. Run narrow tests first.
6. Run the full available test suite before marking complete.
7. For UI changes, add or update accessibility identifiers and screenshot references.
8. For alarm, motion, time-zone, or notification changes, update the manual real-device checklist.

## Quality rules

- Build warnings are treated as failures unless documented.
- Use `Sendable` and actor isolation deliberately; do not silence concurrency warnings indiscriminately.
- No force unwraps in production paths.
- No `try!` in production paths.
- No unbounded retries.
- No hidden analytics.
- No secrets committed to the repository.
- No third-party SDK without a written privacy and maintenance assessment.
- Error messages must tell the user what happened and whether the alarm is still safe.

## UI rules

- Support Dynamic Type, VoiceOver, increased contrast, Reduce Motion, dark mode, 12/24-hour formats, and localization.
- Do not rely on color alone.
- Keep primary alarm status and next ring time visible.
- State explicitly when an alarm remains scheduled.
- Make destructive actions distinct and confirm critical changes.
- Provide a walking-challenge alternative for users who cannot walk or carry the phone.

## Completion report

At the end of each task report:

- task ID
- files changed
- implementation summary
- tests and exact results
- manual verification still required
- risks or limitations
- documentation updated
- recommended next task
