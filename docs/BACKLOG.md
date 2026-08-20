# Claude Code Backlog

Execute one task at a time. A task is complete only when every acceptance criterion passes and evidence is recorded in `docs/IMPLEMENTATION_STATUS.md`.

## Universal task prompt

```text
Implement only <TASK_ID>.

Read CLAUDE.md and the selected task. Inspect before editing.
State a short plan, then implement the smallest coherent change.
Add tests that fail before the fix where practical.
Run narrow and full tests. Do not weaken safety assertions.
Update implementation status and ADRs.
Report changed files, tests, assumptions, risks, and next task.
```

## E00: Product, repository, and engineering governance

### WG-001: Freeze MVP scope and terminology

**Dependencies:** None

**Claude Code instruction:**

> Implement WG-001 only: Freeze MVP scope and terminology. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- A signed-off scope section exists
- All ambiguous terms such as critical alarm, occurrence, local time, and fixed-zone time are defined
- Out-of-scope items are explicit
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-002: Create ADR index and make initial platform decisions

**Dependencies:** WG-001

**Claude Code instruction:**

> Implement WG-002 only: Create ADR index and make initial platform decisions. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- ADR entries cover deployment target, persistence, modularization, and AI provider strategy
- Each decision records tradeoffs and revisit triggers
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-003: Create repository structure and Xcode project

**Dependencies:** WG-002

**Claude Code instruction:**

> Implement WG-003 only: Create repository structure and Xcode project. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- App builds on a clean machine
- Targets and folders match the chosen architecture
- No business logic is placed in the app entry point
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-004: Add formatting, linting, and warning policy

**Dependencies:** WG-003

**Claude Code instruction:**

> Implement WG-004 only: Add formatting, linting, and warning policy. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Formatting and lint commands are documented
- CI fails on agreed warnings
- Generated files are excluded correctly
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-005: Create CI build and unit-test workflow

**Dependencies:** WG-003

**Claude Code instruction:**

> Implement WG-005 only: Create CI build and unit-test workflow. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- CI performs clean build and tests
- Artifacts retain test results
- Secrets are not required for basic CI
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-006: Create implementation status and task tracking

**Dependencies:** WG-001

**Claude Code instruction:**

> Implement WG-006 only: Create implementation status and task tracking. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Every backlog task has status, owner placeholder, and evidence link
- Status changes require acceptance evidence
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-007: Create deterministic test-support module

**Dependencies:** WG-003

**Claude Code instruction:**

> Implement WG-007 only: Create deterministic test-support module. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Fake clock, ID generator, and in-memory repository compile
- Tests demonstrate deterministic time and IDs
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-008: Create threat model and abuse-case register

**Dependencies:** WG-001

**Claude Code instruction:**

> Implement WG-008 only: Create threat model and abuse-case register. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Threats cover alarm suppression, sensor spoofing, prompt injection, privacy leakage, and data corruption
- Each threat has mitigation and test mapping
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E01: Foundation, domain model, and persistence

### WG-010: Define alarm domain models

**Dependencies:** WG-003

**Claude Code instruction:**

> Implement WG-010 only: Define alarm domain models. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Models represent one-time and weekly alarms, criticality, challenge, pre-alarm, and travel policies
- Models are Codable/Sendable where appropriate
- Invalid states are unrepresentable or validated
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-011: Define command, proposal, and audit models

**Dependencies:** WG-010

**Claude Code instruction:**

> Implement WG-011 only: Define command, proposal, and audit models. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Commands and AI proposals are separate types
- Audit event captures actor, before/after, reason, and outcome
- Unknown actor/source values fail safely
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-012: Define repository protocols

**Dependencies:** WG-010

**Claude Code instruction:**

> Implement WG-012 only: Define repository protocols. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Protocols cover alarms, audit events, settings, and outbox operations
- No Apple framework types leak into domain protocols
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-013: Select and configure persistence

**Dependencies:** WG-002, WG-012

**Claude Code instruction:**

> Implement WG-013 only: Select and configure persistence. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Schema is versioned
- In-memory and production repositories share contracts
- Persistence choice is recorded in ADR
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-014: Implement alarm repository

**Dependencies:** WG-013

**Claude Code instruction:**

> Implement WG-014 only: Implement alarm repository. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- CRUD and optimistic revision behavior are tested
- Concurrent updates do not silently overwrite
- Errors are typed
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-015: Implement append-only audit repository

**Dependencies:** WG-013

**Claude Code instruction:**

> Implement WG-015 only: Implement append-only audit repository. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Normal APIs cannot update past audit records
- Queries support user history and diagnostics
- Sensitive fields are excluded
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-016: Implement external-operation outbox

**Dependencies:** WG-013

**Claude Code instruction:**

> Implement WG-016 only: Implement external-operation outbox. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Pending, applied, uncertain, and failed states are represented
- Operations are idempotent
- Recovery is tested
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-017: Add schema migration test harness

**Dependencies:** WG-013

**Claude Code instruction:**

> Implement WG-017 only: Add schema migration test harness. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Fixtures can migrate from every schema version
- Failed migration preserves recoverable data
- Migration tests run in CI
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-018: Add dependency container and environment composition

**Dependencies:** WG-012

**Claude Code instruction:**

> Implement WG-018 only: Add dependency container and environment composition. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Production and test dependency graphs are explicit
- Previews use fakes
- No service locator is accessed from domain code
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-019: Add privacy-safe structured logging

**Dependencies:** WG-008

**Claude Code instruction:**

> Implement WG-019 only: Add privacy-safe structured logging. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Logger redacts sensitive value types
- Release logs omit raw health, location, calendar, journal, and prompts
- Redaction tests exist
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E02: Scheduling engine and AlarmKit integration

### WG-020: Implement pure next-occurrence calculator

**Dependencies:** WG-010, WG-007

**Claude Code instruction:**

> Implement WG-020 only: Implement pure next-occurrence calculator. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- One-time and weekly calculations are deterministic
- The clock and time zone are injected
- Boundary tests cover month/year changes
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-021: Implement wall-clock versus fixed-zone semantics

**Dependencies:** WG-020

**Claude Code instruction:**

> Implement WG-021 only: Implement wall-clock versus fixed-zone semantics. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Follow-local and preserve-original-zone behaviors are distinct
- IANA zone identifiers persist
- Examples are documented
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-022: Handle DST ambiguous and nonexistent times

**Dependencies:** WG-021

**Claude Code instruction:**

> Implement WG-022 only: Handle DST ambiguous and nonexistent times. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Policy for skipped and duplicated local times is explicit
- London, New York, and Lord Howe cases pass
- User-visible resolution is available
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-023: Handle International Date Line and unusual offsets

**Dependencies:** WG-021

**Claude Code instruction:**

> Implement WG-023 only: Handle International Date Line and unusual offsets. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- No unintended duplicate or skipped occurrence in matrix
- 30- and 45-minute zones pass
- Property tests cover random zone changes
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-024: Define AlarmKit adapter protocol and fake

**Dependencies:** WG-010

**Claude Code instruction:**

> Implement WG-024 only: Define AlarmKit adapter protocol and fake. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Protocol supports schedule, cancel, snooze, query, and authorization state
- Fake can inject failures and uncertain outcomes
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-025: Implement AlarmKit authorization flow

**Dependencies:** WG-024

**Claude Code instruction:**

> Implement WG-025 only: Implement AlarmKit authorization flow. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Permission explanation precedes system request
- Denied/restricted states are useful and recoverable
- Settings deep link is available where appropriate
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-026: Implement AlarmKit schedule mapping

**Dependencies:** WG-020, WG-024

**Claude Code instruction:**

> Implement WG-026 only: Implement AlarmKit schedule mapping. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Domain schedules map without losing intent
- External identifiers correlate with local alarms
- Mapping tests cover all supported schedule types
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-027: Implement transactional alarm command processor

**Dependencies:** WG-014, WG-015, WG-016, WG-026

**Claude Code instruction:**

> Implement WG-027 only: Implement transactional alarm command processor. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- All commands pass policy authorization
- Outbox and audit are written around external calls
- Uncertain outcomes trigger reconciliation
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-028: Implement alarm policy engine

**Dependencies:** WG-011

**Claude Code instruction:**

> Implement WG-028 only: Implement alarm policy engine. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Criticality, actor, confirmation, and time-to-fire are evaluated
- AI proposals cannot bypass policy
- A deny reason is user-displayable
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-029: Implement launch and foreground reconciliation

**Dependencies:** WG-027

**Claude Code instruction:**

> Implement WG-029 only: Implement launch and foreground reconciliation. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Missing, extra, and divergent system alarms are detected
- Safe repair is idempotent
- Repairs produce audit events
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-030: Implement schedule/cancel/snooze integration tests

**Dependencies:** WG-027

**Claude Code instruction:**

> Implement WG-030 only: Implement schedule/cancel/snooze integration tests. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Happy path and every injected failure path pass
- Cancellation races are covered
- Tests verify safe persisted outcome
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-031: Create real-device AlarmKit smoke-test checklist

**Dependencies:** WG-026

**Claude Code instruction:**

> Implement WG-031 only: Create real-device AlarmKit smoke-test checklist. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Checklist covers lock screen, silent/focus modes where applicable, app termination, reboot, repeated alarms, and actions
- Results have evidence fields
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E03: Core alarm user experience

### WG-040: Create design tokens and reusable components

**Dependencies:** WG-003

**Claude Code instruction:**

> Implement WG-040 only: Create design tokens and reusable components. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Typography, spacing, surfaces, status, and destructive-action components exist
- Dark mode and Dynamic Type previews pass
- No hard-coded layout assumptions
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-041: Build alarm list and next-alarm summary

**Dependencies:** WG-014, WG-040

**Claude Code instruction:**

> Implement WG-041 only: Build alarm list and next-alarm summary. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Enabled state and next occurrence are accurate
- Empty, loading, error, and reconciliation states exist
- VoiceOver order is logical
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-042: Build create-alarm flow

**Dependencies:** WG-027, WG-040

**Claude Code instruction:**

> Implement WG-042 only: Build create-alarm flow. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- User can create all MVP schedule types
- Next occurrence preview updates before save
- Unsafe/invalid dates cannot be saved
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-043: Build edit, enable, disable, and delete flows

**Dependencies:** WG-041, WG-042

**Claude Code instruction:**

> Implement WG-043 only: Build edit, enable, disable, and delete flows. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Mutations route through command processor
- Critical destructive actions confirm
- Failure leaves a clear safe state
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-044: Build critical alarm configuration

**Dependencies:** WG-028, WG-042

**Claude Code instruction:**

> Implement WG-044 only: Build critical alarm configuration. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Critical behavior is explained in plain language
- Criticality cannot be accidentally toggled by a model
- Tests cover confirmation paths
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-045: Build challenge configuration UI

**Dependencies:** WG-042

**Claude Code instruction:**

> Implement WG-045 only: Build challenge configuration UI. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Ten-second walk and accessible alternatives are configurable
- Phone-carry requirement is disclosed
- Thresholds remain within validated bounds
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-046: Build travel policy UI

**Dependencies:** WG-021, WG-042

**Claude Code instruction:**

> Implement WG-046 only: Build travel policy UI. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Follow local, preserve zone, and ask options are clear
- The UI previews destination behavior
- IANA zone is displayed accessibly
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-047: Build pre-alarm policy UI

**Dependencies:** WG-042

**Claude Code instruction:**

> Implement WG-047 only: Build pre-alarm policy UI. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- User controls prompt windows and allowed actions
- Copy states that no action preserves alarm
- Critical alarm limits are visible
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-048: Build alarm history and audit detail UI

**Dependencies:** WG-015, WG-040

**Claude Code instruction:**

> Implement WG-048 only: Build alarm history and audit detail UI. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- User can understand who/what changed an alarm
- Sensitive internals are not exposed
- Recovery events are distinct
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-049: Add deep links for alarm and proposal screens

**Dependencies:** WG-041

**Claude Code instruction:**

> Implement WG-049 only: Add deep links for alarm and proposal screens. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Notification and AlarmKit actions route safely
- Unknown or stale IDs show a safe error
- Deep links never execute mutations automatically
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-050: Add UI tests for core alarm flows

**Dependencies:** WG-041, WG-049

**Claude Code instruction:**

> Implement WG-050 only: Add UI tests for core alarm flows. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Create/edit/delete/critical/travel flows pass
- Accessibility identifiers are stable
- Screenshots are captured for key states
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-323: `CoreAlarmFlowsUITests` drives a button that no longer exists — WG-050's coverage is dead

**Dependencies:** WG-050

**Claude Code instruction:**

> Implement WG-323 only: **all six** `CoreAlarmFlowsUITests` fail, and have been failing silently, because
> every one of them routes through `app.buttons["addAlarmButton"]` — directly, or via the private
> `createAlarm` helper at line 25. **That identifier does not exist anywhere in `Sources/`.** The alarm-list
> entry point is `addManualAlarmButton` (`AlarmCreationHeader.swift:23`), renamed when the creation header
> gained the describe/manual split; `ScreenshotTourUITests` was updated and this file was not. Verified
> 2026-08-20 by running `make test-ui` in full: 13 tests, **6 failures, all in this class**, all seven tours
> passing. Confirmed pre-existing and unrelated to WG-322 — `git grep addAlarmButton a04ce4a -- Sources/`
> returns nothing. Repair the identifiers so the flows actually run; **do not delete the tests to get a green
> target**, and expect the repair to surface further drift behind the first failure, since nothing in this
> class has executed past its first tap in some time. Preserve every safety invariant.

**Acceptance criteria:**

- `make test-ui` is green in full — **0 failures across the whole target** (13 tests as it stands today) — not merely the tour class. The count is stated as of filing, not as a target to hit: the guard required below may well add a test, and criterion 1 must not read as forbidding it.
- Each repaired test is confirmed to **exercise** its flow rather than to stop passing loudly: check what each
  one asserts after the tap, since a test that has not run in months may assert nothing that still holds.
- The create/edit/delete/critical/travel flows named in WG-050's own acceptance criteria are each demonstrably
  covered again, or the gap is recorded where the criterion is, not left implied.
- A guard against silent recurrence is added or explicitly declined with a reason. Note the general shape:
  **a UI test referencing a stale identifier fails only when someone runs that target**, and `make test-ui` is
  in neither `ci` nor `ci-fast` — which is why this went unnoticed. Whether to add the target to `ci` is
  decided here, on evidence, and recorded.
- `docs/IMPLEMENTATION_STATUS.md`'s WG-050 row is corrected: it currently stands as evidence of coverage that
  has not run.

## E04: Motion sensing and ten-second wake challenge

### WG-060: Define normalized motion source protocols

**Dependencies:** WG-007

**Claude Code instruction:**

> Implement WG-060 only: Define normalized motion source protocols. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Pedometer, activity, device motion, and altimeter are independent ports
- Samples include timestamps and quality
- Unavailable states are explicit
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-061: Implement Motion & Fitness permission flow

**Dependencies:** WG-060

**Claude Code instruction:**

> Implement WG-061 only: Implement Motion & Fitness permission flow. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Permission is requested in context
- Denied state offers alternative challenge
- Purpose copy is specific
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-062: Implement historical pedometer adapter

**Dependencies:** WG-060

**Claude Code instruction:**

> Implement WG-062 only: Implement historical pedometer adapter. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Queries validate intervals and timestamps
- Errors and unavailable hardware are mapped
- No raw sample logging
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-063: Implement live pedometer adapter

**Dependencies:** WG-060

**Claude Code instruction:**

> Implement WG-063 only: Implement live pedometer adapter. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Updates are cancellation-safe
- Duplicate/out-of-order samples are handled
- Tests use recorded traces
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-064: Implement motion activity adapter

**Dependencies:** WG-060

**Claude Code instruction:**

> Implement WG-064 only: Implement motion activity adapter. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Walking/stationary/unknown map to domain values
- Confidence and timestamps are retained
- Unsupported devices degrade safely
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-065: Implement device-carried and pickup evidence

**Dependencies:** WG-060

**Claude Code instruction:**

> Implement WG-065 only: Implement device-carried and pickup evidence. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Evidence distinguishes stationary, pickup, and irregular shaking conservatively
- It does not claim physical displacement
- Battery cost is measured
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-066: Implement optional altimeter evidence

**Dependencies:** WG-060

**Claude Code instruction:**

> Implement WG-066 only: Implement optional altimeter evidence. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Altimeter is supporting evidence only
- Pressure drift does not pass a challenge
- Unavailable barometer has no negative impact
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-067: Implement movement episode builder

**Dependencies:** WG-062, WG-063, WG-064, WG-065

**Claude Code instruction:**

> Implement WG-067 only: Implement movement episode builder. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Multiple streams merge by timestamp
- Pauses, stale samples, and resets are handled
- Trace tests cover bed movement and walking
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-068: Implement wake challenge state machine

**Dependencies:** WG-067

**Claude Code instruction:**

> Implement WG-068 only: Implement wake challenge state machine. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- States include idle, starting, active, passed, failed, timed out, unavailable
- Only valid transitions are possible
- Progress is monotonic or safely reset
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-069: Implement ten-second walking verification

**Dependencies:** WG-068

**Claude Code instruction:**

> Implement WG-069 only: Implement ten-second walking verification. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- A validated walking episode passes
- Short movement and stationary pickup fail
- Thresholds are configurable within safe bounds
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-070: Implement anti-shake and replay defenses

**Dependencies:** WG-069

**Claude Code instruction:**

> Implement WG-070 only: Implement anti-shake and replay defenses. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Rapid irregular motion without pedometer evidence fails
- Duplicate samples cannot inflate progress
- False-positive risk is documented
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-071: Implement challenge UI and progress feedback

**Dependencies:** WG-045, WG-069

**Claude Code instruction:**

> Implement WG-071 only: Implement challenge UI and progress feedback. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Alarm remains clearly active until pass
- Progress is understandable during sleep inertia
- VoiceOver and haptic cues exist
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-072: Implement accessible challenge alternatives

**Dependencies:** WG-068

**Claude Code instruction:**

> Implement WG-072 only: Implement accessible challenge alternatives. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- At least one non-walking alternative exists
- User can preselect it without stigma
- It cannot be invoked by AI
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-073: Connect valid challenge pass to authorized stop

**Dependencies:** WG-027, WG-071

**Claude Code instruction:**

> Implement WG-073 only: Connect valid challenge pass to authorized stop. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Only terminal pass or authorized fallback emits stop command
- Races and duplicate pass callbacks are idempotent
- Audit records the result
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-074: Build motion trace recorder for internal testing

**Dependencies:** WG-060

**Claude Code instruction:**

> Implement WG-074 only: Build motion trace recorder for internal testing. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Debug-only recorder exports anonymized traces
- Production builds exclude it
- Consent warning exists
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-075: Run real-device calibration study

**Dependencies:** WG-074

**Claude Code instruction:**

> Implement WG-075 only: Run real-device calibration study. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Test matrix includes hand, pocket, bag, slow/brisk gait, and shake attempts
- Threshold decision is recorded in ADR
- No participant identifiers are stored
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E05: Pre-alarm movement intelligence

### WG-080: Define deterministic awake-evidence model

**Dependencies:** WG-067

**Claude Code instruction:**

> Implement WG-080 only: Define deterministic awake-evidence model. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Evidence includes recent steps, sustained episode, recency, and optional device interaction
- No single weak signal is conclusive
- Factor contributions are inspectable
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-081: Implement recent movement history query

**Dependencies:** WG-062

**Claude Code instruction:**

> Implement WG-081 only: Implement recent movement history query. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Query window is bounded
- Clock changes and stale samples are handled
- No continuous overnight sensing is required
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-082: Implement pre-alarm evaluator

**Dependencies:** WG-080, WG-081

**Claude Code instruction:**

> Implement WG-082 only: Implement pre-alarm evaluator. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Evaluator only recommends whether to prompt
- Criticality and time remaining influence prompt policy
- Movement never directly cancels
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-083: Implement pre-alarm notification categories and actions

**Dependencies:** WG-082

**Claude Code instruction:**

> Implement WG-083 only: Implement pre-alarm notification categories and actions. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Actions include keep, off today, change time, and remind later as configured
- Warning says original alarm remains unless amended
- Actions are localization-ready
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-084: Implement keep-original action

**Dependencies:** WG-083

**Claude Code instruction:**

> Implement WG-084 only: Implement keep-original action. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- No schedule mutation occurs
- Audit may record acknowledgement without changing alarm
- Stale action is safe
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-085: Implement turn-off-today action

**Dependencies:** WG-083, WG-028

**Claude Code instruction:**

> Implement WG-085 only: Implement turn-off-today action. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Only the occurrence is affected unless explicitly stated
- Critical alarm requires confirmation
- Next recurrence remains correct
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-086: Implement change-time action

**Dependencies:** WG-083, WG-049

**Claude Code instruction:**

> Implement WG-086 only: Implement change-time action. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Action opens an edit proposal, not immediate mutation
- Original remains active until save succeeds
- Race with imminent ring is handled
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-087: Implement remind-later action

**Dependencies:** WG-083

**Claude Code instruction:**

> Implement WG-087 only: Implement remind-later action. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Reminder cannot extend beyond safe bounds
- Critical alarms retain original schedule
- Repeated prompts are capped
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-088: Implement pre-alarm background opportunity handler

**Dependencies:** WG-082

**Claude Code instruction:**

> Implement WG-088 only: Implement pre-alarm background opportunity handler. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- BG task is opportunistic and expiration-safe
- Failure produces no alarm change
- It reschedules responsibly without tight loops
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-089: Implement foreground fallback evaluation

**Dependencies:** WG-082

**Claude Code instruction:**

> Implement WG-089 only: Implement foreground fallback evaluation. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- App launch can evaluate without duplicate prompting
- Prompt suppression uses idempotency keys
- Original alarm remains clear
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-090: Add false-positive feedback loop

**Dependencies:** WG-083

**Claude Code instruction:**

> Implement WG-090 only: Add false-positive feedback loop. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- User can indicate 'I was not awake' or 'helpful'
- Feedback is local and coarse
- It cannot silently retune critical behavior
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-091: Adversarial test bathroom-return-to-bed scenario

**Dependencies:** WG-082

**Claude Code instruction:**

> Implement WG-091 only: Adversarial test bathroom-return-to-bed scenario. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Brief movement produces conservative behavior
- No automatic cancellation occurs
- Test documents expected prompt behavior
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E06: Time-zone, location, and travel behavior

### WG-100: Implement system time-zone observer

**Dependencies:** WG-021

**Claude Code instruction:**

> Implement WG-100 only: Implement system time-zone observer. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Previous and current IANA zones are recorded
- Repeated notifications are idempotent
- Launch reconciliation catches missed events
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-101: Implement travel context domain model

**Dependencies:** WG-100

**Claude Code instruction:**

> Implement WG-101 only: Implement travel context domain model. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Model separates confirmed system zone from optional location context
- Uncertainty and timestamps are represented
- VPN/network state is not mistaken for location
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-102: Implement low-power significant-location adapter

**Dependencies:** WG-101

**Claude Code instruction:**

> Implement WG-102 only: Implement low-power significant-location adapter. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Continuous GPS is not used
- Cached samples are timestamp checked
- Denied permission preserves time-zone functionality
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-103: Implement optional region-monitoring rules

**Dependencies:** WG-101

**Claude Code instruction:**

> Implement WG-103 only: Implement optional region-monitoring rules. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Rules have explicit enable/disable semantics
- Boundary noise is debounced
- Critical alarm fallback is safe
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-104: Implement travel policy evaluator

**Dependencies:** WG-100, WG-101

**Claude Code instruction:**

> Implement WG-104 only: Implement travel policy evaluator. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Follow-local, fixed-zone, and ask policies yield deterministic proposals
- Location cannot silently override system zone
- Evidence is explainable
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-105: Build time-zone change prompt

**Dependencies:** WG-104, WG-049

**Claude Code instruction:**

> Implement WG-105 only: Build time-zone change prompt. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Prompt previews old/new ring times
- No response preserves documented policy
- Critical changes confirm
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-106: Handle DST transition during travel

**Dependencies:** WG-022, WG-104

**Claude Code instruction:**

> Implement WG-106 only: Handle DST transition during travel. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Travel and DST calculations compose correctly
- Ambiguity is surfaced
- Matrix tests pass
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-107: Handle International Date Line travel

**Dependencies:** WG-023, WG-104

**Claude Code instruction:**

> Implement WG-107 only: Handle International Date Line travel. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Occurrences do not duplicate unexpectedly
- User sees date as well as time
- Critical alarm behavior is explicit
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-108: Handle airport/transit and rapid zone changes

**Dependencies:** WG-104

**Claude Code instruction:**

> Implement WG-108 only: Handle airport/transit and rapid zone changes. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Prompt spam is suppressed
- Latest reliable state wins through versioning
- An alarm close to firing is not destabilized
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-109: Build location permission education and controls

**Dependencies:** WG-102, WG-040

**Claude Code instruction:**

> Implement WG-109 only: Build location permission education and controls. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Approximate purpose and battery behavior are explained
- Feature works without permission
- User can disable monitoring
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-110: Create travel real-device/manual simulation matrix

**Dependencies:** WG-105

**Claude Code instruction:**

> Implement WG-110 only: Create travel real-device/manual simulation matrix. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Matrix covers manual zone changes, automatic zone, DST, date line, location denied, and stale callbacks
- Expected alarm outcome is recorded
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E07: HealthKit and wellness intelligence

### WG-120: Define wellness data minimization plan

**Dependencies:** WG-008

**Claude Code instruction:**

> Implement WG-120 only: Define wellness data minimization plan. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Each requested HealthKit type has a user-facing purpose
- Retention and local processing are defined
- Cloud exclusion is explicit
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-121: Implement contextual HealthKit authorization

**Dependencies:** WG-120

**Claude Code instruction:**

> Implement WG-121 only: Implement contextual HealthKit authorization. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Only necessary read types are requested
- Denied and partial access states are supported
- App remains functional
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-122: Implement sleep-analysis query adapter

**Dependencies:** WG-121

**Claude Code instruction:**

> Implement WG-122 only: Implement sleep-analysis query adapter. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Sleep categories map correctly
- Overlapping samples are handled
- Queries are bounded and cancelable
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-123: Implement sleep-duration and consistency calculator

**Dependencies:** WG-122

**Claude Code instruction:**

> Implement WG-123 only: Implement sleep-duration and consistency calculator. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Formula is transparent and unit tested
- Missing data returns unavailable, not fabricated
- Time-zone changes are covered
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-124: Implement conservative sleep-debt estimate

**Dependencies:** WG-123

**Claude Code instruction:**

> Implement WG-124 only: Implement conservative sleep-debt estimate. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- User sleep need is configurable
- Estimate explains assumptions
- No medical claim is made
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-125: Implement readiness factor model

**Dependencies:** WG-123

**Claude Code instruction:**

> Implement WG-125 only: Implement readiness factor model. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Score factors and contributions are deterministic
- Missing factors reduce certainty
- No black-box health diagnosis
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-126: Build readiness explanation UI

**Dependencies:** WG-125, WG-040

**Claude Code instruction:**

> Implement WG-126 only: Build readiness explanation UI. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Every statement maps to a recorded factor
- Uncertainty and missing inputs display
- Copy is nonjudgmental
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-127: Implement evidence-based habit suggestion library

**Dependencies:** WG-125

**Claude Code instruction:**

> Implement WG-127 only: Implement evidence-based habit suggestion library. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Suggestions are static/curated or source-reviewed
- No treatment claims
- Contraindication-sensitive suggestions are excluded
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-128: Add wellness disclaimers and safety copy

**Dependencies:** WG-126

**Claude Code instruction:**

> Implement WG-128 only: Add wellness disclaimers and safety copy. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- App identifies wellness, not medical, scope
- Urgent symptoms are not handled by the AI
- Copy is reviewed for clarity
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-129: Implement health data export/delete controls

**Dependencies:** WG-120

**Claude Code instruction:**

> Implement WG-129 only: Implement health data export/delete controls. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Local derived data can be deleted
- HealthKit source data is not represented as owned by app
- Deletion is audited without retaining deleted content
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-130: Test partial/denied/revoked HealthKit access

**Dependencies:** WG-121, WG-129

**Claude Code instruction:**

> Implement WG-130 only: Test partial/denied/revoked HealthKit access. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Every permission state has expected UI
- Revocation does not crash calculations
- No stale claims remain
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-309: Record interrupted sleep from HealthKit awake segments

**Dependencies:** WG-122, WG-126

**Claude Code instruction:**

> Implement WG-309 only: derive mid-sleep interruptions from the `.awake` segments WG-122 already maps, and surface them on the readiness card. No new HealthKit type, no new sensor, no new permission. Preserve every safety invariant.

**Acceptance criteria:**

- `SleepMetrics.interruptions(_:)` counts only `.awake` spans between first sleep onset and the final wake; settling-in and getting-up awake time is excluded.
- No new HealthKit type is read; the wellness data-minimization plan is unchanged.
- Coarse (#41): a count and a total only — no awake timestamps stored, logged, or displayed.
- `nil` (no asleep data) and `.none` (slept through) are distinct and never conflated.
- Advisory only — never a wake trigger, never on the alarm path.
- Framed as an estimate; no medical claim (#39).
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-310: Motion-based overnight-disturbance estimate

**Dependencies:** WG-309

**Claude Code instruction:**

> Implement WG-310 only: a motion-based fallback estimate of overnight device-handling disturbances for users without Apple sleep tracking, via a retroactive foreground-only motion-activity history query. Preserve every safety invariant.

**Acceptance criteria:**

- Uses a retroactive, foreground-only `CMMotionActivityManager` history query — no background execution, no continuous accelerometer, no new gated entitlement.
- `SleepDisturbanceEstimator` is pure: pickups are maximal runs of moving kinds; `.stationary` and `.unknown` are never counted, so the estimator deliberately under-counts.
- The history source is composed in `AppEnvironment`; the in-memory graph wires a hermetic unavailable source so previews and tests never touch CoreMotion.
- A denied, unavailable, or errored query yields `nil` (no estimate shown), never a fabricated value; `nil` and `.none` stay distinct.
- Presented as an inference of the phone being handled, not measured sleep or confirmed screen-on usage.
- Coarse (#41): a count and a total moving time, no timestamps; the adapter never logs raw activity state.
- The window is bounded well inside CoreMotion's history retention.
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-311: Motion rest-window estimate on the readiness screen

**Dependencies:** WG-310

**Claude Code instruction:**

> Implement WG-311 only: compute the longest contiguous low-activity stretch from the existing WG-310 motion query and show it as supplemental readiness context. It must never enter the readiness score. Preserve every safety invariant.

**Acceptance criteria:**

- One motion query populates both the disturbance and rest estimates.
- The rest estimate is never folded into the readiness score, level, or factors — a still phone is not a sleeping person.
- Readiness still reports "not enough data" when there is no real sleep timeline.
- Framed as low activity, not sleep, under the shared "estimated from movement" caveat; a single duration, no timestamps (#41).
- `nil` (no motion data) and `0` (data exists, always moving) stay distinct; both estimates reset each refresh so a revoked grant leaves no stale value.
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-312: Always-on Movement overnight section

**Dependencies:** WG-310, WG-311

**Claude Code instruction:**

> Implement WG-312 only: compute the motion estimates on every readiness refresh whenever a motion source is wired, and render them as a distinct "Movement overnight" section independent of the HealthKit interruption line. Surfacing change only. Preserve every safety invariant.

**Acceptance criteria:**

- The `lastNightInterruptions == nil` gate is removed; the section shows whenever motion data is available.
- The section has its own header and divider, independent of the interruption line — a Watch user sees both, a non-Watch user sees the movement section only.
- Still never folded into the readiness score; still coarse; still advisory, never on the alarm path.
- No new sensor, permission, or invariant surface is introduced.
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-313: Anchor the overnight motion window to the night, not to the clock

**Dependencies:** WG-310, WG-311

**Claude Code instruction:**

> Implement WG-313 only: replace the rolling `[now - 10h, now]` motion window with a window anchored to the night in the data, so the "Movement overnight" section stops changing every time the screen is opened. Preserve every safety invariant.

**Acceptance criteria:**

- The candidate span is calendar-anchored (previous local evening → now) rather than a rolling lookback from the current instant.
- A night span is derived from the samples: settled = start of the first sustained quiet run, up = end of the last sustained quiet run — mirroring the onset/final-wake shape of `SleepMetrics.interruptions`.
- Disturbances are counted between the bookends, not inside the rest run.
- **Regression test:** identical samples evaluated at two different `now` values (for example 07:00 and 09:00) produce identical disturbance and rest results.
- Post-wake activity and pre-settle evening activity are both excluded; an `.automotive` commute after waking does not increment pickups.
- A DST-transition night and a night spanning a time-zone change are covered by explicit tests; the local anchor is derived through the injected calendar, never a fixed UTC offset.
- `nil` (no data) and `.none` (still night) semantics are preserved exactly.
- New constants (evening anchor, sustained-quiet threshold) carry recorded rationale.
- An ADR records that this supersedes the WG-310 rolling window; mid-sleep opens still shift and that is documented, not fixed.
- The manual real-device checklist is updated (motion and local-time behavior change).
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-314: Night shape — longest unbroken stretch and wake-up length

**Dependencies:** WG-309

**Claude Code instruction:**

> Implement WG-314 only: add the longest unbroken sleep stretch and the longest single awakening to the interruption line, so a user can tell brief wake-ups from a long one, and state that wake-ups are not part of the readiness score. Preserve every safety invariant.

**Acceptance criteria:**

- `SleepMetrics` exposes the longest `.asleep` run uninterrupted by an `.awake` span; `SleepInterruptions` carries the longest single awake span.
- Durations only — no timestamps introduced (#41); no new HealthKit type is read.
- The card distinguishes "all brief" from "one long one" and states the longest unbroken stretch.
- A caption states that wake-ups are not part of the readiness estimate above.
- A slept-through night renders no shape line; missing data yields `nil`, never `0`.
- Singular, plural, and sub-minute edges match the existing interruption-line style.
- New accessibility identifiers are added; the shape line reads as part of the interruption group under VoiceOver and does not truncate at the largest Dynamic Type size.
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-315: Time in bed versus time asleep

**Dependencies:** WG-314

**Claude Code instruction:**

> Implement WG-315 only: surface in-bed duration alongside asleep duration on the readiness card, using the `.inBed` samples already fetched. Preserve every safety invariant.

**Acceptance criteria:**

- `SleepMetrics` exposes in-bed duration from samples already queried; no new HealthKit type is read.
- Two durations are stated plainly. **No percentage and no "sleep efficiency"** — a clinical term, excluded under the no-medical-claims invariant (#39).
- The line is omitted entirely when `.inBed` is absent or shorter than asleep time; bad data produces silence, not a claim.
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-316: Personal baseline for wake-ups

**Dependencies:** WG-314

**Claude Code instruction:**

> Implement WG-316 only: compare last night's wake-up count to the user's own recent median, using the sleep window already fetched. No new query, no new permission. Preserve every safety invariant.

**Acceptance criteria:**

- The baseline is the median wake-up count over prior nights in the existing lookback window, excluding last night.
- At least five prior nights with sleep data are required; below that the line is omitted, never fabricated.
- The comparison is to the user's own history only — no population norms, no targets, no streaks, no good/bad framing.
- Wording is neutral and non-judgemental, consistent with the product language principles.
- Night segmentation reuses the existing gap rule; no second definition of "night" is introduced.
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-317: Model evidence coverage in the motion estimator — the blocker under WG-313 H2 and H3

> **Scope extended 2026-08-19 (round ten): H4, H5 and H6 are in this task, and none of them are reachable by a
> coverage model alone.** **H4** — `nightSpan` closes a block at the *start* of the run that ends it, and the
> disturbance count is taken over that block, so any awakening of `maxDisturbanceGap` or longer is excluded
> from its own count; the worse the night, the more certainly the section reported zero. **H5** —
> `minimumNightDuration` gates the block's *length*, not its quietness, so a stretch that is 77% movement is
> accepted as the night. **H6** — the evening anchor moved the "section changes when you open it" cliff from
> 18:00 to local midnight rather than removing it. All three are pinned as single-assertion `XCTExpectFailure`
> reproductions in `SleepDisturbanceKnownDefectsTests`; a fix must flip those, not just the H2/H3 ones.
> Note that H4 is a *counting-window* defect and H6 a *candidate-span* defect — a design that only adds a
> coverage fraction per block will leave both exactly as they are.

**Dependencies:** WG-313 (H1 portion, landed)

**Why this exists.** `SleepDisturbanceEstimator` cannot distinguish **"still, and observed to be still"** from
**"no data"**. A quiet span means both and nothing in the types says which. WG-313's two remaining defects are
symptoms of that single omission:

- **H2** — a sedentary daytime block can outrank the real night, because blocks are ranked by raw duration and
  a still desk has the same motion signature as a bed.
- **H3** — one stale `.stationary` or low-confidence `.unknown` record fabricates a multi-hour night with zero
  disturbances, because a sample's classification extends across silence.

**Three fixes have been implemented, taken to a green suite, and reverted on adversarial-review evidence** — a
wall-clock night band, a 60-minute trailing validity cap, and zero trailing extrapolation. Each was a
threshold, and each traded a common mild error for a rare severe one. **Do not propose a fourth threshold.**
Full negative results are in the WG-313 ADR in `docs/DECISIONS.md`.

**Claude Code instruction:**

> Implement WG-317 only: give the estimator an explicit representation of how well-evidenced a candidate quiet
> block is, and rank or reject blocks on that basis. Do not add a wall-clock assumption about when the user
> sleeps. No new sensor, permission, or entitlement. Preserve every safety invariant.

**Acceptance criteria:**

- "Observed quiet" and "unobserved" are **distinct in the type system**, not distinguished by a threshold — a
  coverage fraction per block (observed sample-minutes over block duration), a maximum credible unobserved
  stretch, or an `unobserved` span kind alongside `quiet`. The choice is recorded in an ADR with its trade-off
  stated explicitly.
- The rule makes **no assumption about when a human sleeps.** A night-shift worker sleeping 08:30–16:30, a day
  sleeper, and a traveller mid-time-zone-change each still resolve their real night. This is the constraint
  that killed the night band.
- **These three existing tests stay green** — they encode the counter-evidence that falsified the previous
  attempts, and any design that breaks one is wrong for the same reason its predecessor was:
  `testAnEveningOnTheSofaMustNotOutrankAnUnclosedNight`,
  `testAStillSleeperWhoHasNotMovedYetStillGetsANight`,
  `testAQuietGapBetweenTwoRecordsStillResolvesTheWholeNight`.
- **Interior** gaps and **trailing** gaps are handled by the same rule. A phone powered off overnight must not
  report a 14.9h undisturbed night. A trailing-only fix is not a fix — that is what H3 established.
- The four H3 `XCTExpectFailure` reproductions in `SleepDisturbanceSampleValidityTests` and the H2
  reproductions in `SleepDisturbanceNightAnchorTests` flip to passing, and their `XCTExpectFailure` wrappers
  are removed in the same change.
- **Each moving part is mutation-checked independently**, and each is shown to be load-bearing against a
  fixture that covers the real input shape rather than a convenient synthetic one. A mutation check alone is
  insufficient — that is what let the H3 fixture-flattery through. Both checks are required.
- Any change to the shared `classifiedSpans` helper is **parameterized**, not applied to the shared default:
  `estimate` and `longestRestWindow` have their own published WG-310/311 contracts and are not in scope here.
- `nil` (unavailable) versus `.none`/`0` (data existed) is never conflated; under-reporting remains the
  standing bias, and a fabricated night is the failure this task exists to eliminate.
- `motion-red-team` and `ios-architect` are run **before** the commit, and their mutation claims are
  re-verified directly rather than taken on trust.
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

**Follow-on, not in scope:** once coverage is representable it should also be *reported* — telling the user how
much of the night was actually observed. That is a separate surfacing task.

### WG-318: The "Movement overnight" section must never render nothing — say why instead of vanishing

**Dependencies:** WG-312, WG-313

**Why this exists.** The section disappeared entirely whenever there was no estimate — header, both estimates
and the "Estimated from movement" caveat together. Four very different situations produced one identical
outcome (nothing on screen): no motion hardware, Motion & Fitness off or never granted, a restricted
(MDM / parental-controls) device, a transient read failure, and history that resolves no night. The user is
told nothing and can act on nothing. **An empty region is indistinguishable from a bug**, which a
safety-sensitive app may not do.

The most-hit instance is the **cold open**: `refresh` publishes `assessment` before awaiting the motion query
and the card renders as soon as `assessment` is non-nil, so the section was empty on *every* first open for
the duration of the CoreMotion query.

**Claude Code instruction:**

> Implement WG-318 only: make the readiness screen's "Movement overnight" section always render, stating why
> there is no estimate when there isn't one, and distinguishing the causes that have different (or no) user
> actions. Do not add a new sensor, permission, or entitlement. Do not fold anything from this section into
> the readiness score. Preserve every safety invariant.

**Acceptance criteria:**

- The section renders in **every** state, including before the first result has arrived. "No estimate and no
  reason" is **not representable** — enforced by a total type, not by a doc comment or an assertion.
- The distinct causes are distinguishable to the user and in tests: absent hardware, unavailable access,
  restricted access, a transient failure, and no resolvable night. A `MotionSourceError` payload is mapped to
  the reason rather than every throw reporting a permission problem.
- **Copy is true before it is actionable.** No instruction the user cannot carry out on this screen — no
  "pull down to refresh" without a `.refreshable`, no "turn it on in Settings" where no Settings row exists or
  where the grant is not the user's to flip.
- A **cancelled** refresh is not reported as a failure and does not blank an estimate already on screen.
- Overlapping refreshes apply in start order, not completion order; a cancelled newest refresh does not
  starve an older one that produced an answer.
- The cold-open state is reproduced by a failing test **before** the fix, and each moving part is
  mutation-checked independently.
- `docs/DEVICE_SMOKE_TEST.md` is updated in the **same change** — a checklist that certifies the old
  behaviour converts a correct build into a recorded Fail.
- Narrow tests and the full available suite pass; `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

**Not in scope, filed separately:** a `.notDetermined` user still has no way to grant Motion access from this
screen (the adapter throws at the availability guard, before the call that raises the CoreMotion prompt); and
`try?` on the sleep query swallows `CancellationError`, blanking the assessment to "not enough data" while the
movement section is deliberately preserved — pre-existing WG-130 behaviour, not introduced here.

### WG-319: The readiness card must never render an unbounded spinner — the same defect one layer up

**Dependencies:** WG-318

**Why this exists.** WG-318 spent ten rounds removing every way the "Movement overnight" *section* could show
nothing or spin forever. The **card that contains it** was never examined, and it has the identical defect with
a strictly larger blast radius.

`ReadinessScreenContent` renders `ReadinessCardView` only when `model.assessment != nil`, and otherwise a
`ProgressView("Checking your sleep readiness…")` with no bound. `assessment` is assigned in
`ReadinessViewModel.refresh` — *after* `await sleepQuery.sleepSamples(...)`, which has
**no deadline** at either end: not in the view model, and not in `HealthKitSleepQueryAdapter`, which awaits an
`HKSampleQuery` completion handler through a continuation. That is structurally the same shape as
`CoreMotionActivityHistoryAdapter` before WG-318's eighth round — a one-shot framework callback with no
delivery guarantee — and it was accepted then as a real failure worth a deadline.

The consequence is worse than the one WG-318 fixed. The section spinning hid one section; this hides **the
whole card**, including the always-on movement section WG-318 exists to guarantee. The screen has no
`.refreshable` and no scene-phase hook, so nothing re-runs the query for as long as the reader stays on it, and
the user cannot tell it from a slow read. (An earlier version of this paragraph said "terminal for the life of
the process". That is false: `AlarmListView:133` pushes this screen via `NavigationLink`, so navigating back
and re-entering rebuilds the `@State` model and re-runs `.task`. It is an escape, not a mitigation — the screen
never tells the reader it exists.)

**This is the recurring shape, not a new bug.** Every WG-318 fix recreated the bug one layer up — vanishing
section, two nilable optionals, a starved generation guard, a permanent `.loading`. Ask *where has silence
moved to*, not whether the reported case is fixed. It moved to the card.

**Claude Code instruction:**

> Implement WG-319 only: bound the readiness card's load path so a sleep query that never answers cannot leave
> a permanent spinner, and make the card's loading state resolve to something the user can read. Do not add a
> new sensor, permission, or entitlement. Do not change the estimator. Do not fold anything into the readiness
> score. Preserve every safety invariant.

**Acceptance criteria:**

- A sleep query that **never answers** resolves the card within a bounded time. Reproduced by a failing test
  **before** the fix — the defect is a hang, so the reproduction is a test that is killed by
  `-default-test-execution-time-allowance` pre-fix and returns in milliseconds post-fix (the WG-318 round-eight
  artefact, which is cleaner than an assertion).
- The deadline is imposed by the **consumer**, in `ReadinessViewModel`, not in the adapter — the project's own
  `LivePedometerNormalizer:56-58` precedent, and the adapter is device-only and therefore untestable.
- The loser of the race is **abandoned, not awaited**. A structured `withTaskGroup` awaits its cancelled
  children on scope exit and is therefore *inert* against a source that ignores cancellation — exactly the hung
  source a deadline exists for. The double must ignore cancellation so the inert form fails the test.
- A timeout is **not** conflated with a result. Follow `MovementSummary.timedOut`: nothing was read, so a
  timeout must not overwrite a good assessment already on screen with a worse one. The cold-open direction
  (nothing to preserve) must still resolve the spinner.
- `nil` (no result yet) versus an assessment with **no factors** ("not enough data") is never conflated.
- **A read that returned nothing never degrades to the state a *denied* query produces.** This criterion
  originally required the opposite — "a timeout degrades to the same state a denied or errored query already
  produces" — and round twelve falsified it. A denied or revoked grant is a **concluded** read: HealthKit does
  not reveal read denial, so it arrives as an empty sample set, and rendering that as "There isn't enough sleep
  data yet" is true. A timeout, a cancellation or a read *error* learned nothing, and reusing the same strings
  tells a user with fourteen nights in HealthKit that their data is missing. One policy per epistemic
  condition, and "concluded with nothing" and "did not conclude" are two conditions, not one. Errored moved
  sides with them once round thirteen established that a revocation does not throw.
- The state a nothing-was-read outcome resolves to carries **no instruction the reader cannot act on** and
  makes no claim about data that was never looked at.
- Each moving part is **mutation-checked independently**, and the fixtures are separately shown to cover the
  real input shape. Both checks are required; neither substitutes for the other.
- `motion-red-team` and `ios-architect` run **before** the commit, and their mutation claims are re-verified
  from source rather than taken on trust.
- Narrow tests and the full available suite pass; `docs/IMPLEMENTATION_STATUS.md` is updated with evidence and
  `docs/DEVICE_SMOKE_TEST.md` gains the corresponding check.

**Explicitly not in scope, and stated as a limitation rather than fixed:** `ReadinessScreen`'s `.task` also awaits
`HealthAuthorizationCoordinator.requestAccess()` unbounded, before anything is published. That await is
**not** treated as the same defect: it blocks on a modal system sheet the user is looking at, so the spinner
behind it is not a falsehood the reader can see, and the wedged-daemon case is *inferred*, not verified.
Bounding it would also require threading `HealthAuthorizationProviding` through `AppEnvironment` to be
testable at all, which is a separate change. Two related observations recorded here rather than acted on: the
result of `requestAccess()` is discarded (`_ =`) and `isReadinessAvailable(_:)` is never consulted on this
screen; and `ReadinessViewModel` takes a **default** `Calendar(identifier: .gregorian)`, a snapshot of ambient
`TimeZone.current` that `AppEnvironment` never injects and `SystemTimeZoneMonitor` never reaches.

**The denied-grant case is now WG-320, and it is not benign.** This note originally called it so, "because a
denied grant yields no samples and the card already degrades correctly". Round fifteen falsified that:
degrading correctly is exactly what it does *not* do — a user who tapped Don't Allow is told "There isn't
enough sleep data yet" and instructed to add more nights, which is WG-319's own signature defect in its most
common form. WG-319 bounded the **rare** variant (a hung query); every denial, every dismissed sheet and
every simulator run hits the common one.

**Corrected 2026-08-20 (round seventeen):** this paragraph previously blamed the *discarded* `requestAccess()`
result and asserted that the "HealthKit hides read denial" argument is "true of the *query* layer and false of
the *screen*, which has the answer one line above the refresh call." **That is false — the screen has no
answer to discard.** `HKHealthStore.requestAuthorization` does not throw on Don't Allow, so
`HealthKitAuthorizationAdapter` returns `.authorized` for Allow and Don't Allow alike and the summary folds to
`.granted`. The limitation is framework-imposed at *every* layer, so WG-320 is a **copy** fix, not a plumbing
one. Left in place rather than deleted because the false version had already been written into WG-320's
acceptance criteria, where it would have been ticked off without changing anything on a device.

### WG-320: A denied Health grant must not be reported as a shortage of sleep data

**Dependencies:** WG-319

**Why this exists.** WG-319 bounded the *rare* way the readiness card makes a false claim about the user's
data — a HealthKit query that never answers. It left the **common** one untouched, and they are the same
defect: the card says "There isn't enough sleep data yet" and "Add a few nights of sleep data and this will
get more useful" to a user who has just tapped **Don't Allow**.

Every denial, every dismissed sheet, and every simulator run reaches this; the hung-query variant WG-319 fixed
reaches almost nobody.

**This task was filed on a false cause, and was re-scoped 2026-08-20 before any of it was implemented.** As
originally written it blamed `ReadinessScreen` discarding the authorization result (`_ = await
…requestAccess()`) together with `HealthAuthorization.isReadinessAvailable(_:)` being called by nothing in
`Sources/`, and instructed the implementer to "use the authorization result the screen already has."

**There is no such result.** `HKHealthStore.requestAuthorization(toShare:read:)` does not throw when the user
taps Don't Allow — it throws only when authorization cannot be *requested* (Health unavailable, restricted
environment, bad types) — so `HealthKitAuthorizationAdapter` maps Allow and Don't Allow alike to
`.authorized`, and `HealthAccessSummary` folds both to `.granted`. The adapter's own docstring says so. For
this flow `.notDetermined` and `.partial` are unreachable in production, and the old criterion claiming "the
simulator reaches the denied state trivially" was false: tapping Don't Allow in the simulator yields
`.granted`.

**The old version was implementable to green while changing nothing on a device** — thread the provider, stub
it `.denied`, tick every criterion — after which the record would have said the defect was fixed. The
criteria are kept below in corrected form rather than deleted, because that failure mode is the point.

**What is actually true.** Denial and a genuinely empty store are indistinguishable at *every* layer available
to this app, by Apple's design. So the card cannot state the cause. What it can stop doing is asserting one:
"Add a few nights of sleep data and this will get more useful." is an unfollowable instruction aimed at a
user whose real problem may be a permission switch two taps away.

**Claude Code instruction:**

> Implement WG-320 only: change what the readiness card **says** on the empty-result path so it is true
> whether the store is genuinely empty or the read was silently unauthorized, and so it names the one thing
> the reader can actually check. Do **not** thread the authorization result through in order to branch on a
> denial — no layer can detect one, and a card that says "access is off" when it is on is the defect
> `ReadinessUnavailability` exists to prevent. Do not add a new sensor, permission, or entitlement. Do not
> change the estimator or the readiness score. Do not bound `requestAccess()` itself — that remains WG-319's
> stated limitation. Preserve every safety invariant.

**Acceptance criteria:**

- The empty-result copy is **true under both readings** — genuinely no data, and denied-so-no-data — and
  asserts neither. It must not tell the user they have too little sleep data, because that is not known.
  Reproduced by a failing test **before** the fix.
- It names the **one action the reader can take**: checking Health access for Alarm Agent in Settings. That
  is followable from where they stand, unlike "add a few nights of sleep data", and unlike a retry this
  screen cannot perform. The standing branch rule holds — no instruction the reader cannot act on, and no
  glyph promising an affordance that does not exist.
  **Unresolved tension, flagged 2026-08-20 — settle it before implementing, do not discover it mid-fix.** For
  the user whose store is *genuinely* empty (every simulator run, every new user), "check Health access" is
  exactly as unfollowable as "add a few nights": they open Settings, find the toggle already on, and learn
  nothing. That is the same dead end `testNoMessageSendsTheUserToASettingsToggleThatCannotHelp` already
  forbids for `ReadinessUnavailability`, and it sits against this task's own instruction that "a card that can
  only guess must not assert either way". There is no test-level conflict today — the prohibition suite covers
  `ReadinessUnavailability`, while this copy lives on the `ReadinessExplanation` path — so this is a
  specification question, not a defect: decide whether the Settings pointer is offered as *a thing worth
  checking* (survivable under both readings) or as *the cause* (false under one of them).
- **All three strings on this path are in scope**, not the two the reader notices first:
  `ReadinessExplanation.swift:48` ("There isn't enough sleep data yet…"), `:57` ("Add a few nights of sleep
  data…"), **and** the factor list built inline at `ReadinessCardView.swift` ("We don't have enough data yet
  for: …"). The third is `private` to the view and reachable by no copy test, which is exactly the
  "copy no test can reach is copy no rule applies to" case — and WG-319's own suite already treats it as one
  of the three false claims (`ReadinessColdOpenClaimTests.testATimedOutColdOpenDoesNotListEveryFactorAsMissing`).
  A fix that leaves it in place is not this task done.
- **No new case is added to distinguish denial**, and no test stubs an authorization status **as evidence that
  the user tapped Don't Allow**. Note the narrower wording, corrected 2026-08-20: an earlier version forbade
  stubbing `.denied` "as though production could produce one", which is **false** — production reaches
  `.denied` whenever the *request itself* fails, since `HealthKitAuthorizationAdapter` fails closed to
  `.restricted` for every type and `HealthAccessSummary.of` folds that to `.denied`. That route is real and
  `HealthAuthorizationCoordinatorTests` covers it correctly for this very flow; read literally, the old
  criterion asked for those tests to be deleted. What is unreachable is `.denied` *meaning a user declined*.
  If a future iOS release exposes read authorization, that is a new task with new evidence.
- The copy is tested with an **exhaustive positive `switch`**, not a set of prohibitions: a prohibition suite
  constrains the multiset of strings and never the case→meaning binding, which this branch has already shipped
  a defect through. **Name the type it switches over.** There is no `CaseIterable` reason type on this path
  today — the copy comes from `private static func summary(for: ReadinessLevel?)` and
  `certaintyNote(for:hasData:)` — so satisfy this either by anchoring to `ReadinessLevel` (adding
  `CaseIterable`) plus the `hasData: false` case, or by moving the empty-result copy behind a small
  `CaseIterable` type the way `MovementUnavailability` was. Left unanchored, it will be ticked against
  whichever enum is convenient — most likely `ReadinessUnavailability`, which is **not** the path being fixed.
- `HealthKitAuthorizationAdapter`'s contract is **documented at the adapter, not pinned by a test** — a
  `// WHY:` on `requestReadAccess` recording that the non-throwing branch covers Allow *and* Don't Allow
  alike, pointing here. Corrected 2026-08-20: the earlier criterion demanded *a test* pinning it, which is
  **not achievable** — the adapter holds a `private let store = HKHealthStore()` with no injection seam,
  `statuses(for:_:)` is `private`, no test in the repo touches any device-only adapter, and WG-319's own ADR
  justifies its consumer-side deadline on that same untestability. Demanding a test here would either license
  a lookalike that pins the *port* (`HealthAuthorizationCoordinator` over a stub provider) and therefore would
  **not** have caught the original filing, or silently require the very plumbing this task's instruction
  forbids. Nothing pins the mapping today, so a future contributor can still "fix" it by inventing a
  `.denied` the framework never supplies; the comment is the guard, and its absence is the gap.
- **Keep the new copy in the app layer**, alongside `MovementUnavailability`'s. The replacement sentence names
  the display name ("Alarm Agent") and a Settings action; both live in `Sources/WakeGuardApp` today, and
  putting product naming into `Sources/HealthDomain/ReadinessExplanation.swift` pushes app-shell concerns into
  the domain layer (ARCHITECTURE §1).
- The always-on movement section still renders on this path — a sleep-side shortage must not hide it, which
  is the guarantee WG-318 exists to make.
- Each moving part is **mutation-checked independently**, with a control, and the fixtures are separately shown
  to cover the real input shape.
- `motion-red-team` and `ios-architect` run **before** the commit, and their mutation claims — surviving ones
  included — are re-verified by running them rather than taken on trust.
- Narrow tests and the full available suite pass; `docs/IMPLEMENTATION_STATUS.md` gains an evidence row and
  `docs/DEVICE_SMOKE_TEST.md` the corresponding check — which supersedes SMK-17 step 6, currently marked
  expected-to-fail. Real hardware still matters, but not for the reason the old criterion gave: what needs a
  device is confirming the *revoked-after-granted* path renders the new copy, not reaching a "denied state"
  that no layer reports.

### WG-321: A restricted device is told its permanent sleep-read failure is momentary

**Dependencies:** WG-319

**Claude Code instruction:**

> Implement WG-321 only: on a **restricted** device, `ReadinessUnavailability.temporarilyUnavailable`'s "We
> couldn't check your sleep readiness **just now**." is false — the failure is permanent, not momentary.
> Verified path: `HKHealthStore.requestAuthorization` throws in an MDM / parental-controls environment,
> `HealthKitAuthorizationAdapter.requestReadAccess` fails closed to `.restricted` for every type,
> `ReadinessScreen` **discards** that result, `refresh` runs the query anyway, and the query errors — arriving
> as `SleepReadOutcome.failed` and rendering the one unavailable case. For that user it is every attempt,
> forever, and the card asks them to wait for something that will never resolve. The sibling section already
> models exactly this distinction (`MovementUnavailability.accessRestricted`, "Settings won't change this");
> the sleep path collapses it. Note this is a **different** situation from WG-320's: a denial is undetectable
> at every layer, whereas a restriction **is** reported, and thrown away one line above the refresh call.
> Do not add a new sensor, permission, or entitlement. Do not change the estimator or the readiness score.
> Preserve every safety invariant.

**Acceptance criteria:**

- A test reproduces the false claim **before** the fix: a restricted authorization result plus a failing read
  renders a message asserting transience. It must fail for that reason, not merely be absent.
- The restricted case is distinguishable from a transient read failure **in what the card says**. Whether that
  is a second `ReadinessUnavailability` case or a different routing is an implementation choice, but the
  one-case docstring must be corrected either way — it currently enumerates three causes while the arm catches
  four, which is what hid this.
- The copy names no action the reader can take **when there is none**, and says so plainly rather than
  implying waiting will help. Mirror `MovementUnavailability.accessRestricted`'s framing; do not invent a
  Settings instruction a supervised user cannot follow.
- Whatever consumes `requestAccess()`'s result consumes it **deliberately** — the current `_ =` discard is the
  actual root cause, and it is the one place on this screen where an authorization answer genuinely exists.
  This is explicitly **not** the WG-320 case and must not be justified by WG-320's "no layer knows" finding.
- The copy is covered by an **exhaustive positive `switch`**, and the cross-type check that the readiness and
  movement failure lines differ still holds — both render on one card at once.
- SMK-17 gains the restricted-device observation it currently disclaims, or records why it cannot be reached.
- `motion-red-team` and `ios-architect` run **before** the commit; mutation claims are re-verified by running.

### WG-322: The readiness card's `.unavailable` branch is exercised end to end by nothing

**Dependencies:** WG-319

**Claude Code instruction:**

> Implement WG-322 only: close the **M4** coverage gap. `ReadinessDisplayState.cardContent`'s `.unavailable`
> arm was mutated to `return nil` during WG-319 round fourteen and **survived all 1435 tests** — restoring the
> permanent spinner, the hidden card and the hidden always-on movement section, which is precisely the defect
> WG-319 exists to remove. Unit coverage was added (`ReadinessDisplayStateTests`), but it asserts on the
> display state, and **no check at any layer observes what the reader actually sees on that branch**: the
> identifiers `readinessUnavailableReason` and `readinessLoading` are referenced by nothing anywhere, no step
> in `SMK-17` reaches the card, and `ScreenshotTourUITests` lands in `.assessed` because the `-uiTesting`
> graph's `UnavailableSleepQuery` returns `[]` rather than throwing. Add a debug-only launch argument that
> composes a **failing** sleep read, and a tour case that asserts the card on that branch before snapping it.
> Do not add a new sensor, permission, or entitlement. Do not change the estimator, the readiness score, the
> deadline, or any user-facing copy. Preserve every safety invariant.

**Acceptance criteria:**

- The new tour case **fails when M4 is re-applied** (`cardContent`'s `.unavailable` arm rewritten to
  `return nil`) and passes on the unmutated tree. The mutation is run, not reasoned about — this criterion is
  the whole task, and a test that merely reaches the branch without discriminating M4 does not satisfy it.
- It asserts positively that `readinessUnavailableReason` is on screen, so it cannot pass vacuously by the
  screen failing to load, and asserts `readinessLoading` is **absent** — the spinner is the defect.
- It asserts the **movement section survives a failed sleep read** (`readinessMovementHeader` present). That
  is WG-318's always-on guarantee under WG-319's failure branch, and no test observes the pair today.
- It asserts the card makes **no data-shortage claim** on this branch (`readinessSummary` and
  `readinessMissing` absent) — round twelve's defect, currently pinned only at the unit layer.
- The launch argument is unreachable in Release. Name it so it contains the substring `-uiTesting`, which puts
  it under the existing `ReleaseReadinessTests.testUITestingHookIsUnreachableInRelease` walk for free; do not
  add a second, parallel gate.
- `testTour4ReadinessDegraded` still lands in `.assessed` and still passes. The existing double is not
  replaced — a graph that can only fail would delete the success coverage WG-318 round nine added.
- `docs/DEVICE_SMOKE_TEST.md`'s SMK-17 coverage-gap note is updated: it currently states this hole as open and
  prescribes "a never-answering sleep query", which is **not** what should be built — a throwing query reaches
  the same arm instantly, while a hang costs 15s and depends on a `sleepTimeout` the graph cannot inject.
- Whether `make test-ui` should join `ci` / `ci-fast` is decided and recorded, not left implied.

## E08: Calendar and morning planning

### WG-140: Define calendar data minimization and redaction

**Dependencies:** WG-008

**Claude Code instruction:**

> Implement WG-140 only: Define calendar data minimization and redaction. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Only fields needed for wake planning are retained
- Titles/notes remain local
- Model-facing summaries are redacted
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-141: Implement contextual EventKit authorization

**Dependencies:** WG-140

**Claude Code instruction:**

> Implement WG-141 only: Implement contextual EventKit authorization. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Full read access is requested only when user enables calendar planning
- Denied state is useful
- Purpose string is specific
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-142: Implement upcoming-event adapter

**Dependencies:** WG-141

**Claude Code instruction:**

> Implement WG-142 only: Implement upcoming-event adapter. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Queries are bounded by time and selected calendars
- All-day and time-zone-aware events map correctly
- No raw titles in logs
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-143: Implement user-confirmed critical event marking

**Dependencies:** WG-142

**Claude Code instruction:**

> Implement WG-143 only: Implement user-confirmed critical event marking. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- The user, not the LLM, confirms criticality
- Critical marking is reversible
- Evidence is audited
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-144: Implement morning preparation profile

**Dependencies:** WG-010

**Claude Code instruction:**

> Implement WG-144 only: Implement morning preparation profile. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Preparation, travel, and safety buffers are explicit
- Defaults are editable
- No location or calendar permission is required
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-145: Implement latest-safe-wake calculator

**Dependencies:** WG-142, WG-144

**Claude Code instruction:**

> Implement WG-145 only: Implement latest-safe-wake calculator. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Calculation is pure and transparent
- Conflicting events and all-day events are handled
- Results include uncertainty
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-146: Build tomorrow-plan recommendation screen

**Dependencies:** WG-145, WG-040

**Claude Code instruction:**

> Implement WG-146 only: Build tomorrow-plan recommendation screen. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Existing alarm remains visible
- Recommendation shows reason and buffers
- Apply requires explicit action
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-147: Implement calendar-change refresh

**Dependencies:** WG-142, WG-146

**Claude Code instruction:**

> Implement WG-147 only: Implement calendar-change refresh. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Changes invalidate stale proposals
- No automatic critical mutation occurs
- Prompt frequency is bounded
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-148: Test hostile or misleading event text

**Dependencies:** WG-140, WG-142

**Claude Code instruction:**

> Implement WG-148 only: Test hostile or misleading event text. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Calendar text cannot inject model/tool instructions
- Displayed text is safely rendered
- Redaction is verified
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E09: On-device AI and agentic workflow

### WG-160: Define LanguageModelProvider protocol and fake

**Dependencies:** WG-011

**Claude Code instruction:**

> Implement WG-160 only: Define LanguageModelProvider protocol and fake. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Provider returns typed results or typed failures
- No alarm tools are exposed
- Fake supports malformed and adversarial output
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-161: Define structured schemas for AI use cases

**Dependencies:** WG-160

**Claude Code instruction:**

> Implement WG-161 only: Define structured schemas for AI use cases. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Schemas exist for alarm intent, tomorrow plan, explanation, journal extraction, and policy preference
- Enums and numeric bounds are constrained
- Unknown fields fail or are ignored safely by policy
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-162: Implement Apple Foundation Models availability gate

**Dependencies:** WG-160

**Claude Code instruction:**

> Implement WG-162 only: Implement Apple Foundation Models availability gate. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Unsupported/unavailable states produce deterministic fallback
- No AI feature blocks alarm use
- Availability is visible in settings
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-163: Implement on-device structured generation adapter

**Dependencies:** WG-161, WG-162

**Claude Code instruction:**

> Implement WG-163 only: Implement on-device structured generation adapter. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Guided/structured generation decodes into domain DTOs
- Cancellation and refusal are handled
- Raw prompts are not logged
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-164: Implement natural-language alarm parser

**Dependencies:** WG-163

**Claude Code instruction:**

> Implement WG-164 only: Implement natural-language alarm parser. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Ambiguous date/time requests produce clarification UI or bounded choices
- Parser cannot create critical status
- Preview precedes save
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-165: Implement deterministic alarm intent validator

**Dependencies:** WG-164

**Claude Code instruction:**

> Implement WG-165 only: Implement deterministic alarm intent validator. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Past dates, invalid zones, unsupported recurrence, and unsafe values reject
- Validation is independent of model
- Tests include adversarial text
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-166: Build conversational alarm creation UI

**Dependencies:** WG-164, WG-165

**Claude Code instruction:**

> Implement WG-166 only: Build conversational alarm creation UI. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- User sees parsed schedule and assumptions
- Nothing schedules before confirmation
- Fallback manual editor is one tap away
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-167: Implement Tomorrow Agent context builder

**Dependencies:** WG-125, WG-145

**Claude Code instruction:**

> Implement WG-167 only: Implement Tomorrow Agent context builder. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Context uses minimized structured factors
- Sensitive raw text is excluded
- Missing permissions are represented
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-168: Implement Tomorrow Agent proposal generation

**Dependencies:** WG-163, WG-167

**Claude Code instruction:**

> Implement WG-168 only: Implement Tomorrow Agent proposal generation. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Output is a bounded proposal, not a command
- Reasons reference actual factors
- Critical schedule changes require confirmation
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-169: Implement explanation generator grounded in factor IDs

**Dependencies:** WG-163

**Claude Code instruction:**

> Implement WG-169 only: Implement explanation generator grounded in factor IDs. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Every claim cites an internal factor ID
- Unsupported claims are dropped
- Deterministic template fallback exists
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-170: Implement conversational sleep-journal extraction

**Dependencies:** WG-163

**Claude Code instruction:**

> Implement WG-170 only: Implement conversational sleep-journal extraction. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- User text maps to structured optional fields
- Original journal remains local
- Associations are not called causation
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-171: Implement agent permission settings

**Dependencies:** WG-028, WG-040

**Claude Code instruction:**

> Implement WG-171 only: Implement agent permission settings. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Modes include recommend only and ask before acting
- Auto-adjust is disabled for MVP or tightly bounded by ADR
- Critical alarms remain immutable without confirmation
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-172: Implement AgentOrchestrator and policy handoff

**Dependencies:** WG-168, WG-171

**Claude Code instruction:**

> Implement WG-172 only: Implement AgentOrchestrator and policy handoff. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Orchestrator cannot access AlarmKit or repositories directly
- All proposals pass schema and policy
- Audit distinguishes AI proposal from user action
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-173: Implement prompt-injection defenses

**Dependencies:** WG-148, WG-172

**Claude Code instruction:**

> Implement WG-173 only: Implement prompt-injection defenses. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Untrusted text is clearly delimited and minimized
- Instructions in calendar/journal content cannot alter policy
- Red-team tests exist
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-174: Implement optional cloud-provider interface behind feature flag

**Dependencies:** WG-160, WG-120

**Claude Code instruction:**

> Implement WG-174 only: Implement optional cloud-provider interface behind feature flag. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Disabled by default
- Requires explicit separate consent
- Sensitive default-deny redaction is enforced
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-175: Create AI evaluation corpus

**Dependencies:** WG-161

**Claude Code instruction:**

> Implement WG-175 only: Create AI evaluation corpus. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Corpus covers ambiguous dates, time zones, critical events, manipulative prompts, and missing context
- Expected structured outputs and policy decisions are versioned
- No real personal data
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-176: Run AI hallucination and safety evaluation

**Dependencies:** WG-175

**Claude Code instruction:**

> Implement WG-176 only: Run AI hallucination and safety evaluation. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Invalid schedule rate and unsupported-claim rate are measured
- All alarm mutations remain policy-controlled
- Failures produce backlog fixes
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E10: Privacy, security, and compliance

### WG-180: Build permission and consent center

**Dependencies:** WG-040

**Claude Code instruction:**

> Implement WG-180 only: Build permission and consent center. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Alarm, notifications, motion, location, health, calendar, and cloud AI are separate
- Current status and purpose display
- Revocation guidance exists
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-181: Implement sensitive-data classification types

**Dependencies:** WG-019

**Claude Code instruction:**

> Implement WG-181 only: Implement sensitive-data classification types. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Sensitive values cannot be logged through normal APIs
- Cloud-bound builders require redacted types
- Compiler boundaries are used where practical
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-182: Implement local data retention controls

**Dependencies:** WG-013

**Claude Code instruction:**

> Implement WG-182 only: Implement local data retention controls. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Retention applies to derived motion, audit, recommendations, and journal separately
- Critical audit minimum is documented
- Cleanup is tested
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-183: Implement full local export

**Dependencies:** WG-012

**Claude Code instruction:**

> Implement WG-183 only: Implement full local export. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Export is user-initiated and clearly labeled
- Sensitive export is protected by system share UI
- Schema version is included
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-184: Implement accountless local deletion/reset

**Dependencies:** WG-182

**Claude Code instruction:**

> Implement WG-184 only: Implement accountless local deletion/reset. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- User can delete optional data categories or all app data
- Scheduled alarm consequences are explicitly confirmed
- Deletion is complete and tested
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-185: Audit Keychain and secret handling

**Dependencies:** WG-174

**Claude Code instruction:**

> Implement WG-185 only: Audit Keychain and secret handling. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- No keys in source or UserDefaults
- Cloud tokens are revocable
- Logs never contain secrets
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-186: Create privacy manifest and SDK inventory

**Dependencies:** WG-003

**Claude Code instruction:**

> Implement WG-186 only: Create privacy manifest and SDK inventory. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Required reason APIs are documented
- Every SDK has data-use justification
- Unused SDKs are removed
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-187: Draft App Privacy Nutrition Label mapping

**Dependencies:** WG-120, WG-140, WG-186

**Claude Code instruction:**

> Implement WG-187 only: Draft App Privacy Nutrition Label mapping. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Every transmitted data type and use is accounted for
- Optional collection is still documented where required
- Mapping matches app behavior
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-188: Draft in-app and web privacy policy requirements

**Dependencies:** WG-187

**Claude Code instruction:**

> Implement WG-188 only: Draft in-app and web privacy policy requirements. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Collection, use, sharing, retention, deletion, and AI providers are explicit
- Health and motion advertising prohibition is explicit
- Contact path exists
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-189: Run static security and dependency audit

**Dependencies:** WG-185, WG-186

**Claude Code instruction:**

> Implement WG-189 only: Run static security and dependency audit. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Known vulnerable dependencies are absent or justified
- Network endpoints and entitlements are inventoried
- Findings are triaged
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-190: Run privacy leak test on logs and analytics

**Dependencies:** WG-181

**Claude Code instruction:**

> Implement WG-190 only: Run privacy leak test on logs and analytics. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Automated fixtures scan for names, titles, coordinates, health samples, journal text, and prompts
- No release log leak remains
- Regression test is in CI
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-191: Prepare App Review notes and demo mode

**Dependencies:** WG-188

**Claude Code instruction:**

> Implement WG-191 only: Prepare App Review notes and demo mode. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Reviewer can test alarms and optional permissions
- Safety behavior is explained
- No fake capabilities are claimed
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E11: Accessibility, localization, and visual quality

### WG-200: Implement progressive onboarding

**Dependencies:** WG-040, WG-180

**Claude Code instruction:**

> Implement WG-200 only: Implement progressive onboarding. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Only alarm essentials are requested initially
- Optional permissions are feature-triggered
- Skip paths remain useful
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-201: Complete VoiceOver labels, values, hints, and focus order

**Dependencies:** WG-041

**Claude Code instruction:**

> Implement WG-201 only: Complete VoiceOver labels, values, hints, and focus order. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Core flows are usable eyes-free
- Alarm status and destructive consequences are announced
- Automated checks plus manual audit pass
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-202: Complete Dynamic Type and layout stress test

**Dependencies:** WG-040

**Claude Code instruction:**

> Implement WG-202 only: Complete Dynamic Type and layout stress test. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Largest accessibility sizes do not clip critical content
- Controls remain reachable
- No horizontal scrolling in core flows
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-203: Implement Reduce Motion and haptic alternatives

**Dependencies:** WG-071

**Claude Code instruction:**

> Implement WG-203 only: Implement Reduce Motion and haptic alternatives. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Animations respect Reduce Motion
- Haptics are supplementary
- Progress remains understandable
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-204: Complete contrast and non-color status audit

**Dependencies:** WG-040

**Claude Code instruction:**

> Implement WG-204 only: Complete contrast and non-color status audit. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- All statuses have text/icon redundancy
- Dark and light modes pass
- Critical warnings are distinguishable
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-205: Implement 12/24-hour and locale-aware formatting

**Dependencies:** WG-020

**Claude Code instruction:**

> Implement WG-205 only: Implement 12/24-hour and locale-aware formatting. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Formatting follows user locale
- Stored schedules remain locale-independent
- Tests cover multiple calendars/locales where supported
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-206: Externalize and localize all user-facing strings

**Dependencies:** WG-083

**Claude Code instruction:**

> Implement WG-206 only: Externalize and localize all user-facing strings. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- No production strings remain hard-coded
- Pluralization and interpolation are safe
- Permission strings are localized
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-207: Test right-to-left layout

**Dependencies:** WG-206

**Claude Code instruction:**

> Implement WG-207 only: Test right-to-left layout. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Navigation, time rows, progress, and destructive actions mirror correctly
- Icons with directionality are reviewed
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-208: Run sleep-inertia usability review

**Dependencies:** WG-071, WG-200

**Claude Code instruction:**

> Implement WG-208 only: Run sleep-inertia usability review. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Ringing/challenge screens have minimal choices
- Copy is short and concrete
- Accidental destructive taps are reduced
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-209: Run aesthetic consistency epoch

**Dependencies:** WG-041, WG-208

**Claude Code instruction:**

> Implement WG-209 only: Run aesthetic consistency epoch. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Spacing, typography, iconography, corner treatment, animation, and empty states are consistent
- Every screen has a visual hierarchy
- Before/after screenshots are reviewed
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-210: Run device-size and orientation visual regression

**Dependencies:** WG-209

**Claude Code instruction:**

> Implement WG-210 only: Run device-size and orientation visual regression. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Minimum and current supported devices pass
- Landscape behavior is intentional
- Screenshot diffs are triaged
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E12: Reliability, performance, battery, and observability

### WG-220: Implement coarse privacy-safe analytics abstraction

**Dependencies:** WG-019, WG-187

**Claude Code instruction:**

> Implement WG-220 only: Implement coarse privacy-safe analytics abstraction. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- No SDK is required for local development
- Event schema forbids sensitive payloads
- Analytics can be fully disabled
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-221: Implement crash diagnostics redaction

**Dependencies:** WG-181

**Claude Code instruction:**

> Implement WG-221 only: Implement crash diagnostics redaction. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Breadcrumbs contain no raw sensitive data
- Correlation IDs link to local audit safely
- User can opt out where applicable
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-222: Measure cold-launch and reconciliation performance

**Dependencies:** WG-029

**Claude Code instruction:**

> Implement WG-222 only: Measure cold-launch and reconciliation performance. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Baseline and budget are documented
- Large alarm histories are tested
- Slow paths are profiled
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-223: Measure overnight battery baseline

**Dependencies:** WG-063, WG-088, WG-102

**Claude Code instruction:**

> Implement WG-223 only: Measure overnight battery baseline. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Tests compare features off/on
- Continuous sensing regressions are detected
- Budget and device conditions are documented
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-224: Optimize motion challenge battery and responsiveness

**Dependencies:** WG-223

**Claude Code instruction:**

> Implement WG-224 only: Optimize motion challenge battery and responsiveness. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Sensors start only when needed
- Pass latency meets target
- No unnecessary high-frequency sampling
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-225: Optimize location and background scheduling

**Dependencies:** WG-223

**Claude Code instruction:**

> Implement WG-225 only: Optimize location and background scheduling. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- No continuous GPS
- BG requests are not spammed
- Travel functionality survives throttling
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-226: Stress-test alarm command concurrency

**Dependencies:** WG-027

**Claude Code instruction:**

> Implement WG-226 only: Stress-test alarm command concurrency. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Simultaneous edit/action/time-zone/reconciliation events serialize safely
- No lost update
- Idempotency holds
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-227: Stress-test persistence corruption and recovery

**Dependencies:** WG-017, WG-029

**Claude Code instruction:**

> Implement WG-227 only: Stress-test persistence corruption and recovery. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Recoverable data is preserved
- Unsafe ambiguity keeps alarms scheduled and alerts user
- Recovery is audited
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-228: Run 100-cycle alarm/challenge soak test

**Dependencies:** WG-073

**Claude Code instruction:**

> Implement WG-228 only: Run 100-cycle alarm/challenge soak test. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- No crash, leak, or stale challenge state
- Duplicate callbacks do not accumulate
- Results are documented
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-229: Run background expiration and termination tests

**Dependencies:** WG-088, WG-029

**Claude Code instruction:**

> Implement WG-229 only: Run background expiration and termination tests. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Expiration handlers complete safely
- Termination never causes a silent mutation
- Reconciliation repairs uncertainty
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-230: Build operational diagnostics screen

**Dependencies:** WG-029, WG-221

**Claude Code instruction:**

> Implement WG-230 only: Build operational diagnostics screen. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Shows permission status, reconciliation state, last safe schedule sync, and redacted errors
- No sensitive raw data
- Export is user initiated
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E13: Adversarial review and stabilization epochs

### WG-240: Epoch 1: independent architecture and invariant review

**Dependencies:** WG-030, WG-075

**Claude Code instruction:**

> Implement WG-240 only: Epoch 1: independent architecture and invariant review. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Reviewer maps every invariant to code and tests
- Violations become blocking issues
- No feature work proceeds with open P0
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-241: Epoch 2: functional bug hunt

**Dependencies:** WG-240

**Claude Code instruction:**

> Implement WG-241 only: Epoch 2: functional bug hunt. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Reviewers attempt normal and abnormal core flows
- Each bug has reproduction, severity, and regression test
- All P0/P1 fixed
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-242: Epoch 3: time, DST, recurrence, and travel red team

**Dependencies:** WG-110

**Claude Code instruction:**

> Implement WG-242 only: Epoch 3: time, DST, recurrence, and travel red team. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Automated matrix and manual simulations run
- Date-line and DST bugs receive regression tests
- Critical behavior remains explicit
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-243: Epoch 4: motion spoofing and false inference red team

**Dependencies:** WG-075, WG-091

**Claude Code instruction:**

> Implement WG-243 only: Epoch 4: motion spoofing and false inference red team. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Shake, bed movement, phone handoff, delayed samples, and replay attacks are tested
- Threshold changes are evidence-based
- Accessible paths remain available
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-244: Epoch 5: background, reboot, permission, and race chaos

**Dependencies:** WG-229

**Claude Code instruction:**

> Implement WG-244 only: Epoch 5: background, reboot, permission, and race chaos. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Kill/relaunch/revoke/expire/duplicate/out-of-order scenarios run
- No silent suppression
- Uncertain state reconciles
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-245: Epoch 6: AI prompt injection and hallucination red team

**Dependencies:** WG-176

**Claude Code instruction:**

> Implement WG-245 only: Epoch 6: AI prompt injection and hallucination red team. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Untrusted calendar/journal text cannot issue commands
- Malformed output fails closed
- Every unsupported claim is removed or labeled
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-246: Epoch 7: privacy and security review

**Dependencies:** WG-190

**Claude Code instruction:**

> Implement WG-246 only: Epoch 7: privacy and security review. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Data-flow map matches code
- No sensitive analytics/logging/cloud leak
- Threat model is updated
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-247: Epoch 8: accessibility review with assistive settings

**Dependencies:** WG-201, WG-207

**Claude Code instruction:**

> Implement WG-247 only: Epoch 8: accessibility review with assistive settings. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- VoiceOver, Switch Control considerations, Dynamic Type, Reduce Motion, contrast, and alternatives are evaluated
- Blockers fixed
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-248: Epoch 9: aesthetic and interaction polish

**Dependencies:** WG-209, WG-210

**Claude Code instruction:**

> Implement WG-248 only: Epoch 9: aesthetic and interaction polish. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Visual hierarchy, copy, transitions, states, and consistency are reviewed independently
- Cosmetic defects are tracked separately from functional defects
- Approved screenshot baseline is created
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-249: Epoch 10: battery and performance regression

**Dependencies:** WG-222, WG-225

**Claude Code instruction:**

> Implement WG-249 only: Epoch 10: battery and performance regression. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Budgets pass on representative devices
- Hot paths have profiles
- Regressions are fixed or feature-flagged off
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-250: Epoch 11: App Store compliance preflight

**Dependencies:** WG-191, WG-246

**Claude Code instruction:**

> Implement WG-250 only: Epoch 11: App Store compliance preflight. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Entitlements, permission strings, privacy labels, review notes, subscriptions if any, and claims are checked
- No reviewer-only hacks
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-251: Epoch 12: release-candidate bug bash

**Dependencies:** WG-241, WG-250

**Claude Code instruction:**

> Implement WG-251 only: Epoch 12: release-candidate bug bash. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Fresh testers execute critical scripts
- All findings triaged
- No P0/P1 and accepted P2 list is explicit
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-252: Run final regression after fixes

**Dependencies:** WG-251

**Claude Code instruction:**

> Implement WG-252 only: Run final regression after fixes. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Every fixed defect has a passing regression test
- Full automated and manual critical matrix reruns
- Release candidate is immutable except blocker fixes
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E14: TestFlight, App Store, and post-release

### WG-260: Create internal TestFlight build pipeline

**Dependencies:** WG-005, WG-250

**Claude Code instruction:**

> Implement WG-260 only: Create internal TestFlight build pipeline. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Signed archive uploads repeatably
- Release notes and build metadata are generated
- Debug tools are absent
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-261: Recruit staged beta cohorts and consent

**Dependencies:** WG-260

**Claude Code instruction:**

> Implement WG-261 only: Recruit staged beta cohorts and consent. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Cohorts cover travelers, heavy snoozers, accessibility needs, and varied devices
- Feedback collection avoids sensitive data
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-262: Run two-week alarm reliability beta

**Dependencies:** WG-261

**Claude Code instruction:**

> Implement WG-262 only: Run two-week alarm reliability beta. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Alarm success/failure reports have reproducible evidence
- No silent suppression incident remains unexplained
- Kill switches are validated
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-263: Run travel and time-zone beta

**Dependencies:** WG-261

**Claude Code instruction:**

> Implement WG-263 only: Run travel and time-zone beta. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Real trips or controlled simulations validate behavior
- Prompt usefulness and confusion are measured
- Bugs feed back into epoch 3
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-264: Run motion challenge calibration beta

**Dependencies:** WG-261

**Claude Code instruction:**

> Implement WG-264 only: Run motion challenge calibration beta. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- False pass/fail feedback is collected locally/coarsely
- Threshold changes are versioned
- Accessibility alternatives are evaluated
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-265: Run AI usefulness and safety beta

**Dependencies:** WG-261, WG-176

**Claude Code instruction:**

> Implement WG-265 only: Run AI usefulness and safety beta. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Proposal acceptance, edit rate, invalid output, and explanation trust are measured
- No autonomous critical mutation
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-266: Finalize support, FAQ, privacy, and safety pages

**Dependencies:** WG-188, WG-262

**Claude Code instruction:**

> Implement WG-266 only: Finalize support, FAQ, privacy, and safety pages. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Troubleshooting covers permissions, unavailable sensors, travel, and missed alarms
- Claims match actual behavior
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-267: Finalize App Store metadata and screenshots

**Dependencies:** WG-248, WG-266

**Claude Code instruction:**

> Implement WG-267 only: Finalize App Store metadata and screenshots. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Screenshots reflect shipping UI
- Metadata avoids medical claims
- Core differentiator is clear
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-268: Submit release candidate and handle review feedback

**Dependencies:** WG-252, WG-267

**Claude Code instruction:**

> Implement WG-268 only: Submit release candidate and handle review feedback. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Review responses are factual
- Any code change restarts relevant release gates
- No hidden behavior
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-269: Prepare rollback and smart-feature kill-switch plan

**Dependencies:** WG-220, WG-268

**Claude Code instruction:**

> Implement WG-269 only: Prepare rollback and smart-feature kill-switch plan. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Smart features can be disabled without affecting scheduled alarms
- Version rollback implications are documented
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-270: Post-release monitoring and incident process

**Dependencies:** WG-268

**Claude Code instruction:**

> Implement WG-270 only: Post-release monitoring and incident process. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Alarm reliability incidents receive highest priority
- Privacy incident procedure exists
- Metrics remain coarse and consented
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-271: Thirty-day post-launch review

**Dependencies:** WG-270

**Claude Code instruction:**

> Implement WG-271 only: Thirty-day post-launch review. Preserve every safety invariant. Inspect the current architecture, add the minimum production code and tests required, update documentation, and stop after the acceptance criteria pass.

**Acceptance criteria:**

- Reliability, battery, accessibility, retention, and support data are reviewed
- Next-phase features require a new scope decision
- Narrow tests and the full available suite pass.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

## E15: Opt-in telemetry (TelemetryDeck)

Opt-in, privacy-first product + reliability + crash telemetry via TelemetryDeck, behind the existing
`AnalyticsSink` port (WG-220). Off by default, disclosed, consented, never on the alarm critical path. Full
design in `docs/TELEMETRY_PLAN.md`.

### WG-272: Telemetry ADR + third-party privacy/maintenance assessment

**Dependencies:** WG-220

**Claude Code instruction:**

> Implement WG-272 only: the decision record + third-party assessment authorizing opt-in TelemetryDeck
> telemetry. Docs-only — no product code, no dependency, no manifest/label change. Preserve every safety
> invariant. This task records the human approval that unblocks WG-273–279.

**Acceptance criteria:**

- `docs/DECISIONS.md` ADR records the vendor choice, the rejection of Firebase/GA, off-by-default + consent
  model, the closed-schema guarantee, the critical-path rule, and data residency.
- `docs/THIRD_PARTY_TELEMETRYDECK.md` assessment exists (data flows, subprocessors, retention, SDK size,
  update cadence, removal plan) per the CLAUDE.md third-party-SDK rule.
- Human approval to proceed is recorded.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-273: Add the TelemetryDeck Swift package

**Dependencies:** WG-272

**Claude Code instruction:**

> Implement WG-273 only: add the TelemetryDeck SPM dependency (the project's first third-party package),
> pinned to an exact version, with no behaviour change yet. Preserve every safety invariant.

**Acceptance criteria:**

- `project.yml` gains a top-level `packages:` entry + the target dependency, pinned to an exact `from:`.
- `Package.resolved` committed; the project resolves and builds; `make ci-fast` green.
- No sink wired yet (no runtime behaviour change).
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-274: TelemetryDeckSink adapter (wired, off by default)

**Dependencies:** WG-273

**Claude Code instruction:**

> Implement WG-274 only: a `TelemetryDeckSink: AnalyticsSink` mapping each closed `AnalyticsEvent` to a
> TelemetryDeck signal, initialised with crash reporting enabled and the App ID from build config; wire it
> into `AppEnvironment` behind `GatedAnalytics`, production-only, **off by default**. Preserve every safety
> invariant.

**Acceptance criteria:**

- With `analyticsEnabled == false` (default) nothing is emitted (unit test asserts the gate drops all).
- `inMemory()` graph uses `NoOpAnalyticsSink`; the App ID is read from config, not a literal.
- `ConsentFlagBox` bridges the synchronous gate to async settings.
- Narrow tests and the full available suite pass; `docs/IMPLEMENTATION_STATUS.md` updated with evidence.

### WG-275: Dedicated opt-in consent step (honored live)

**Dependencies:** WG-274

**Claude Code instruction:**

> Implement WG-275 only: a dedicated onboarding consent step + a Privacy-settings toggle bound to
> `analyticsEnabled`, opt-in, honest copy, honored on the next event without relaunch. Preserve every safety
> invariant and every UI rule (Dynamic Type, VoiceOver, contrast, localization).

**Acceptance criteria:**

- Default stays off; toggling on then off is honored live (test).
- Dedicated onboarding consent screen with a clear decline that leaves telemetry off.
- Accessibility + localization per the UI rules.
- Narrow tests and the full available suite pass; `docs/IMPLEMENTATION_STATUS.md` updated with evidence.

### WG-276: Instrument call sites (product + reliability)

**Dependencies:** WG-274

**Claude Code instruction:**

> Implement WG-276 only: extend the closed `AnalyticsEvent` enum with the reliability events
> (`alarmScheduled`, `reconcileOutcome`, `permissionResolved`, `appLaunched`) and emit all events
> fire-and-forget at their call sites. Never on the alarm critical path. Preserve every safety invariant.

**Acceptance criteria:**

- New cases carry only coarse, closed values (a leak-scan test proves no sensitive payload is representable).
- Emissions never `await`-block scheduling / reconcile / challenge completion.
- `reconcileOutcome` is emitted from the existing `RecordingAlarmCommandProcessor` seam.
- Narrow tests and the full available suite pass; `docs/IMPLEMENTATION_STATUS.md` updated with evidence.

### WG-277: Disclosure — nutrition label + privacy manifest

**Dependencies:** WG-272, WG-274

**Claude Code instruction:**

> Implement WG-277 only: update `PrivacyNutritionLabel`, `PrivacyInfo.xcprivacy`, and their pinned tests to
> the honest opt-in-telemetry state (Product Interaction + Crash Data, not linked, not tracking). This
> changes pinned privacy assertions — requires the WG-272 ADR + recorded approval. Preserve every other
> safety invariant.

**Acceptance criteria:**

- Nutrition label, privacy manifest, and `transmittedDataTypes` are consistent and honest; tracking flag
  stays false.
- `PrivacyNutritionLabelTests` + `PrivacyManifestTests` updated to the new state under the ADR.
- Narrow tests and the full available suite pass; `docs/IMPLEMENTATION_STATUS.md` updated with evidence.

### WG-278: Telemetry test matrix

**Dependencies:** WG-275, WG-276, WG-277

**Claude Code instruction:**

> Implement WG-278 only: the telemetry test matrix — consent on/off honored live, structurally leak-proof,
> critical-path isolation, offline degrades silently, disclosure consistency, config-not-secret. Preserve
> every safety invariant.

**Acceptance criteria:**

- All matrix cases pass in `make ci-fast`.
- A manual device line (verify a signal lands in the dashboard on device) is added to the checklist.
- `docs/IMPLEMENTATION_STATUS.md` is updated with evidence.

### WG-279: Rollout, kill-switch, and disclosure docs

**Dependencies:** WG-278

**Claude Code instruction:**

> Implement WG-279 only: confirm the consent toggle is the kill-switch (off → zero emission), document the
> remote-free disable, and update the release checklist, testability report, App Store data questionnaire
> answer, and privacy policy. Preserve every safety invariant.

**Acceptance criteria:**

- Consent-off proven to emit nothing; the no-backend disable path is documented.
- `RELEASE_CHECKLIST.md`, `TESTABILITY_REPORT.md`, and the App Store data-collection answer are updated and
  mutually consistent with the manifest/label.
- Narrow tests and the full available suite pass; `docs/IMPLEMENTATION_STATUS.md` updated with evidence.
