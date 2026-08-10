# Threat Model & Abuse-Case Register (WG-008)

WakeGuard is safety-sensitive: its job is to **wake the user reliably** and to **protect sensitive
sleep, health, motion, location, and calendar data**. This register enumerates the abuse cases that
would violate those goals, the mitigation that prevents each (by design and by `SAFETY_INVARIANTS.md`
number), and the automated test(s) that hold the mitigation in place. It is a living document: a new
sensitive surface or mutation path must be added here with its mitigation and test.

Scope note: the on-device AI (E09) is **scaffolded** today (`AIApplication`/`AIInfrastructure` are
placeholders). Its threats are listed with their **architectural** mitigations, which are already
enforced by the module boundaries; the constrained-decoding tests land with E09.

Severity: **Critical** = a user could fail to wake, or sensitive data could leak. **High** = incorrect
behavior with a safe fallback. **Medium** = degraded UX, no safety/privacy impact.

---

## 1. Alarm suppression (Critical)

The core failure: a critical alarm does not ring, or is silently cancelled/delayed.

| Abuse case | Mitigation (invariant) | Tests |
|---|---|---|
| A movement/awake inference silently suppresses the alarm | A movement inference **never** suppresses an alarm — it can at most surface an advisory prompt (#8). The evaluator/pipeline hold no alarm authority. | `BathroomReturnToBedScenarioTests`, `PreAlarmEvaluatorTests`, `PreAlarmPipelineTests` |
| A pre-alarm prompt turns off a critical alarm without consent | A critical/imminent change is **confirmation-gated** (#6); no response leaves the alarm unchanged (#7). | `DefaultAlarmPolicyEngineTests`, `PreAlarmNotificationResponderTests` (critical turn-off → `.needsConfirmation`), `PreAlarmChangeTimeIntegrationTests` |
| A tapped notification action mutates the wrong alarm / a corrupt notification mis-routes | The `userInfo` payload decodes **fail-closed**; a corrupt/foreign notification is ignored (#7). | `PreAlarmNotificationResponderTests` (payload fail-closed) |
| A failed/denied/interrupted system schedule loses the alarm | Persist-first (source of truth), then reconcile; a failed placement is **repaired, never dropped** (#10). Not-authorized is a recoverable **deferral**, not a hard failure. | `AlarmSchedulingIntegrationTests`, `AlarmReconcilerTests`, `AlarmReconciliationTests` |
| A DST spring-forward gap silently skips a wake-up | A gap fires at the gap's **end** — never skipped — for one-time **and** weekly, any DST delta (incl. 30/45-min zones). | `AlarmSchedulingEngineTests`, `AlarmSchedulingDateLineTests` |
| An International Date Line day-skip loses a one-time alarm | The alarm fires at the same wall-clock on the **next existing day**, flagged, never lost. | `AlarmSchedulingDateLineTests` |
| A missed background run drops the alarm | Background execution is **opportunistic**; a critical alarm rings even if the `BGTaskScheduler` run never happens (#9). | `PreAlarmBackgroundRunnerTests`, `PreAlarmBackgroundWorkTests` |
| A challenge failure/timeout stops the alarm anyway | A failed/timed-out/unavailable challenge **never** stops the ring; only a genuine pass does, exactly once. | `ChallengeStopTests`, `WalkVerificationTests` |

## 2. Sensor spoofing (High)

Faked motion/pedometer/altimeter data to falsely pass the wake challenge or falsely conclude "awake".

| Abuse case | Mitigation | Tests |
|---|---|---|
| Shaking the phone in place to fake a walk | Cadence-regularity / anti-shake gate: only plausible sustained gait passes; a metronome-regular or irregular shake is rejected. | `CadenceRegularityTests`, `WalkVerificationTests`, `WakeChallengeTests` |
| A single strong signal fakes "awake" | The awake model requires **corroboration across factors** — no lone signal reaches `.likely` (structural clamp). | `AwakeEvidenceTests`, `BathroomReturnToBedScenarioTests` |
| A device jostled in transit (car/train) reads as awake | Tolerated **advisory** residual only — it can at most prompt, never suppress (#8); documented, not hidden. | `AwakeEvidenceTests`, `PreAlarmEvaluatorTests` |
| An unavailable sensor is read as "confirmed still" | Fail-closed: "couldn't observe" is distinct from "confirmed still" and never nudges (`.sourceUnavailable`). | `RecentMovementQueryTests`, `BathroomReturnToBedScenarioTests`, `MotionSourceTests` |
| A tilt/pickup spoofs the still→awake evidence | Device-motion evidence is calibration-gated and never the sole wake gate (the walk challenge is). | `DeviceMotionEvidenceTests`, `AltitudeEvidenceTests` |

## 3. Prompt injection / AI overreach (Critical — architectural)

Malicious or adversarial content reaching the on-device AI (E09) coercing an unsafe action.

| Abuse case | Mitigation (invariant) | Enforcement |
|---|---|---|
| The model calls AlarmKit / cancels an alarm directly | **AI cannot call AlarmKit** (#1) and **cannot mutate persistence** — it only proposes. | Module boundaries + `domain_no_apple_frameworks` / composition-root lint rules; `AlarmApplication` is Foundation-only |
| A model output is executed as an unconstrained command | AI output is **decoded into constrained structured types**, and every proposed mutation passes through `AlarmPolicyEngine`. | `AlarmPolicyEngine` is the sole mutation authority (WG-028); constrained-decode tests land with **E09** |
| A model escalates an alarm to critical | **Only the user/policy assigns criticality — never a model** (#31). | `DefaultAlarmPolicyEngineTests`, `PreAlarmFeedbackTests` (feedback references no alarm authority) |
| A prompt embeds sensitive data that then leaks | Prompts containing sensitive data are **never logged** (#41) — see §4. | see §4 |

## 4. Privacy leakage (Critical)

Raw health, precise location, calendar titles, journal text, sleep-revealing timestamps, or LLM prompts
persisted, logged, or transmitted.

| Abuse case | Mitigation (invariant) | Tests |
|---|---|---|
| Raw pedometer/motion samples written to a log | Adapters **never log raw samples or framework error text** — a failure surfaces only as a coarse state (#41). | `HistoricalPedometerTests`, `LivePedometerTests`, `MotionTraceRecorderTests` |
| Pre-alarm feedback stores sleep-revealing data | Feedback is an **aggregate two-counter tally** — no id, occurrence/fire time, timestamp, or sample (#41); a recursive no-PII scan pins it. | `PreAlarmFeedbackTests`, `CoreDataPreAlarmFeedbackStoreTests` |
| An AlarmKit error leaks the alarm title | Errors map to a **coarse** typed reason, never raw error text (#41). | `SystemAlarmManagerAdapterTests` (redaction), `AlarmManagerAdapterTests` |
| Location tracked continuously / coordinates stored | **Low-power significant-location only** (`startMonitoringSignificantLocationChanges` — never continuous GPS); stores **only a coarse movement timestamp, never coordinates** (#41); a denied permission preserves time-zone travel detection. | `SignificantLocationTests` (WG-102) |
| Data used for advertising / off-device processing | On-device processing + data minimization; no third-party SDK without a written assessment. | design + `RELEASE_CHECKLIST.md` privacy section |
| Structured logs include sensitive value types | The privacy-safe logger's `Redacted` carries **only a category, never the raw value** — so raw health/location/calendar/journal/prompt/sample values are structurally impossible to log, in every build (#41). | `PrivacyLogTests` |

## 5. Data corruption (High)

Corrupt or malformed persisted state producing a crash, a lost alarm, or a wrong decision.

| Abuse case | Mitigation | Tests |
|---|---|---|
| An unknown persisted enum value crashes or mis-decodes | String-raw enums decode **fail-closed** to a safe value (#27). | `AwakeEvidenceTests`, `PreAlarmNotificationResponderTests` (payload), `MotionSourceTests` |
| A `.distantFuture`-derived key traps on `Int` overflow | Whole-second **`Double`** truncation for any `Date`-derived key — never `Int(...)` (which traps on `.distantFuture`). | `CoreDataPreAlarmPromptLedgerTests`, `PreAlarmNotificationResponderTests` |
| Step/duration overflow traps | **Saturating** arithmetic (`addingReportingOverflow`), never raw `+`. | `AwakeEvidenceTests`, `RecentMovementQueryTests` |
| Concurrent duplicate claims corrupt the prompt ledger | Uniqueness-constrained **atomic idempotent** claim; a losing concurrent write rolls back, fail-closed. | `CoreDataPreAlarmPromptLedgerTests` |
| A schema migration loses recoverable alarm data | Additive lightweight migration; a **migration test harness** proves every version migrates and a failed migration preserves recoverable data. | **WG-017** (`MigrationTests`) |
| A corrupt store makes the app render "no alarms" | An unreadable store surfaces an **explicit failure**, never a silent empty (#10). | `AlarmListViewModelTests`, `PreAlarmBackgroundWorkTests` (unreadable repo posts nothing) |
| Every mutation is untraceable | Every mutation writes an **append-only audit event** (actor, reason, old/new, timestamp) (#46). | `CoreDataAuditRepositoryTests`, `CommandProposalAuditTests`, `AlarmCommandProcessorTests` |

---

## Residual risks & follow-ups

- **AI constrained-decoding tests** land with E09 (the path is scaffolded; the boundary guarantees hold today).
- **On-device ring verification** (AlarmKit/UNUserNotifications/BGTaskScheduler) is device-only — tracked in `RELEASE_CHECKLIST.md`, not unit tests.
- The pre-alarm **reminder-cap persistence** and the **change-time-from-notification** UI are advisory-only follow-ups (documented in `DECISIONS.md`) — neither affects whether an alarm rings (#9).
