# Architecture

## 1. Layering

```text
SwiftUI Views
    ↓
Feature ViewModels / Coordinators
    ↓
Application Use Cases
    ↓
Domain Models + Pure Policy/Calculation Engines
    ↓
Ports / Protocols
    ↓
Apple Framework Adapters + Persistence + Model Providers
```

The domain layer imports Foundation only where practical. It does not import AlarmKit, CoreMotion, CoreLocation, HealthKit, EventKit, UserNotifications, or FoundationModels.

## 2. Suggested modules

- `WakeGuardApp`
- `DesignSystem`
- `AlarmDomain`
- `AlarmApplication`
- `AlarmInfrastructure`
- `MotionDomain`
- `MotionInfrastructure`
- `TravelDomain`
- `TravelInfrastructure`
- `HealthDomain`
- `HealthInfrastructure`
- `CalendarInfrastructure`
- `AIApplication`
- `AIInfrastructure`
- `PrivacySecurity`
- `Observability`
- `TestSupport`

Use packages only where they reduce coupling without making iteration cumbersome. A feature-folder structure inside one target is acceptable initially, provided boundaries are enforced by protocols and tests.

## 3. Core domain models

### Alarm

- id
- label
- enabled
- schedule rule
- travel behavior
- criticality
- sound
- snooze policy
- challenge policy
- pre-alarm policy
- created/updated timestamps
- revision

### ScheduleRule

- one-time zoned date/time
- weekly wall-clock recurrence
- original time-zone identifier
- local-time behavior
- next occurrence calculation

### ChallengePolicy

- mode
- target duration
- minimum steps
- maximum cadence
- allowed pauses
- anti-cheat threshold
- accessible fallback
- calibration profile reference

### AlarmCommand

- create
- update
- enable
- disable
- cancel occurrence
- reschedule occurrence
- snooze
- mark challenge passed
- reconcile
- recover

### AlarmProposal

- proposed command
- human-readable explanation
- evidence references
- confidence band
- expiry
- model/provider metadata

### AuditEvent

- actor
- command
- old state hash
- new state hash
- timestamp
- source
- outcome
- correlation ID
- user-visible reason

## 4. Principal services

### AlarmSchedulingEngine

Pure calculations for next occurrences, DST handling, wall-clock versus fixed-zone behavior, and date-line behavior.

### AlarmPolicyEngine

Authorizes commands based on criticality, source, user confirmation, time remaining, permissions, and feature settings.

### AlarmCommandProcessor

Applies an authorized command transactionally to local state and AlarmKit through an outbox/reconciliation pattern.

### AlarmReconciler

Compares desired persisted alarms with system alarms and repairs safe divergences.

### WakeVerificationEngine

State machine that consumes normalized motion samples and produces progress, pass, fail, timeout, or unavailable.

### MovementEpisodeBuilder

Converts pedometer, motion activity, device motion, and optional altimeter signals into bounded episodes.

### PreAlarmEvaluator

Computes deterministic “possibly awake” evidence and decides whether a prompt is warranted. It never mutates alarms.

### TravelContextEngine

Combines time-zone notifications, low-power location context, and alarm travel policy.

### ReadinessCalculator

Transparent deterministic scoring. Stores factor contributions for explainability.

### AgentOrchestrator

Calls a model only for approved use cases, validates structured output, and returns proposals or explanations.

### SensitiveDataRedactor

Removes titles, notes, coordinates, identifiers, and raw health values from logs and cloud-bound content.

## 5. Persistence

Recommended first choice: SwiftData or Core Data with an explicit repository layer. Select one in an ADR after evaluating migration, testability, and background access.

Use:

- versioned schemas;
- migrations tested from every shipped version;
- an outbox for pending external AlarmKit operations;
- append-only audit events;
- encrypted secrets in Keychain;
- no raw model prompt logging.

## 6. Concurrency

- Use actors for mutable shared services.
- Keep one alarm command serialization boundary.
- Make external adapter operations cancellation-aware.
- Use idempotency keys for retries.
- Reconcile after uncertain outcomes.
- Never assume an async cancellation means the external operation did not occur.

## 7. Background execution

`BGTaskScheduler` may refresh recommendations, query recent samples, or reconcile opportunistically. It is not a precise timer and must not be required for alarm correctness.

AlarmKit remains the system alarm authority. Actionable notifications are used for pre-alarm prompts. Time-zone notifications and location callbacks are handled when delivered, with launch-time reconciliation as backup.

## 8. AI provider strategy

```text
User input / deterministic context
    ↓
Prompt builder with data minimization
    ↓
LanguageModelProvider protocol
    ├── Apple Foundation Models provider
    ├── deterministic fake provider
    └── optional cloud provider behind explicit opt-in
    ↓
Structured response decoder
    ↓
Schema validator
    ↓
AlarmPolicyEngine
    ↓
Proposal UI or authorized command
```

No model provider receives a direct reference to AlarmKit or persistence.

## 9. Observability

Allowed examples:

- alarm_schedule_attempt_succeeded
- alarm_reconciliation_detected_divergence
- challenge_started
- challenge_passed with coarse duration bucket
- travel_prompt_shown
- proposal_accepted

Disallowed examples:

- exact sleep stage timeline
- exact coordinates
- calendar title
- journal content
- raw motion stream
- model prompt containing personal data

## 10. Feature flags and kill switches

Maintain local/remote-capable flags for:

- pre-alarm prompt generation
- automatic low-risk proposal preparation
- cloud AI
- location context
- readiness score
- experimental anti-cheat
- optional analytics

A kill switch may disable smart behavior but must not disable existing scheduled alarms.
