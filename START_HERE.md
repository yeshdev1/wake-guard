# WakeGuard: Claude Code Execution Pack

This pack is designed to be dropped into the root of a new or existing iOS repository and executed one small task at a time with Claude Code.

**Placeholder product name:** WakeGuard  
**Recommended MVP deployment target:** iOS 26+  
**Implementation:** Swift 6, SwiftUI, AlarmKit, Core Motion, optional Core Location, optional HealthKit, optional EventKit, Foundation Models where available  
**Primary promise:** A dependable alarm that can require a verified 10-second walk, notices likely early waking, adapts safely to travel, and uses AI only behind deterministic policy and explicit permissions.

## Nonnegotiable product rule

The LLM may interpret, recommend, summarize, and prepare a proposed change. It must never directly cancel, delay, suppress, or weaken a critical alarm.

No user response means the original alarm remains scheduled and rings at the original set time.

## How to use this pack

1. Copy this directory's contents into the repository root.
2. Open Claude Code in the repository.
3. Begin with the bootstrap prompt below.
4. Execute one backlog task per branch or worktree.
5. Run the required review epoch after each milestone.
6. Do not start AI work until the deterministic alarm and motion vertical slice passes real-device testing.

## Bootstrap prompt for Claude Code

```text
Read CLAUDE.md, docs/PRODUCT_SPEC.md, docs/ARCHITECTURE.md,
docs/SAFETY_INVARIANTS.md, docs/TEST_STRATEGY.md, and docs/BACKLOG.md.

Then:
1. Inspect the repository without changing files.
2. Report the current state, missing prerequisites, and the next unblocked task.
3. Create or update docs/IMPLEMENTATION_STATUS.md with a task checklist.
4. Do not implement more than one backlog task.
5. Propose the exact task ID you will execute first and explain why.
```

## Prompt for each implementation task

```text
/run-task <TASK_ID>
```

Or paste:

```text
Implement only task <TASK_ID> from docs/BACKLOG.md.

Follow CLAUDE.md and all safety invariants.
First inspect relevant code and state a short implementation plan.
Write or update tests before finishing.
Use protocol-backed clocks, sensors, schedulers, and model providers.
Run the narrow tests, then the full available test suite.
Do not refactor unrelated code.
Do not weaken an existing assertion to make tests pass.
Update docs/IMPLEMENTATION_STATUS.md and docs/DECISIONS.md.
Return:
- files changed
- behavior implemented
- tests run and results
- assumptions
- remaining risks
- next unblocked task
```

## Recommended milestone order

1. Foundation and deterministic alarm scheduling.
2. Complete alarm UI and state reconciliation.
3. Ten-second walk challenge on real devices.
4. Pre-alarm movement prompt.
5. Time-zone and travel behavior.
6. Optional HealthKit and calendar intelligence.
7. On-device AI interpretation and explanations.
8. Adversarial, privacy, accessibility, battery, and visual-polish epochs.
9. TestFlight and App Store release gates.

## Definition of shippable

The app is not shippable merely because it compiles. It must:

- Preserve scheduled alarms through app termination, device lock, reboot scenarios supported by the platform, and ordinary permission changes.
- Never silently cancel or delay an alarm because of AI or an uncertain movement inference.
- Pass a real-device time-zone, DST, sensor, battery, accessibility, and notification-action test matrix.
- Provide a non-motion accessibility alternative to the walking challenge.
- Explain permissions before requesting them and remain useful when optional permissions are denied.
- Keep raw health, motion, calendar, and location data on device unless the user explicitly opts into a clearly disclosed cloud feature.
- Have an auditable record of every alarm mutation and its actor.
- Meet the release gates in docs/RELEASE_CHECKLIST.md.
