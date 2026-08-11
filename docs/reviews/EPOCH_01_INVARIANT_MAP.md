# Epoch 1 (WG-240): Architecture & invariant review

Two independent adversarial reviewers (ios-architect + alarm-safety-reviewer) mapped every one of the 50
`SAFETY_INVARIANTS.md` invariants to its enforcing code and its regression test, and hunted for any that is
claimed but not actually protected.

**Verdict: no open P0.** The alarm-authority chain, auditability, privacy, and cloud boundaries are enforced
*and* tested. One P1 (anti-shake gate not wired) and three P2 cleanups are tracked below.

## Invariant → code → test map

| # | Invariant | Enforced in | Pinned by |
|---|---|---|---|
| 1 | AlarmKit only via the adapter | `AlarmInfrastructure/SystemAlarmManagerAdapter` (sole `import AlarmKit`) + `.swiftlint.yml` domain rule | `AgentOrchestratorTests`, `SafetyEvaluationTests` source-scans |
| 2 | Only `AlarmCommandProcessor` invokes the adapter | `AlarmApplication/AlarmCommandProcessor` | `AlarmAuthorizationFlowTests.testFlowNeverMutatesAlarms` |
| 3 | Every command authorized by the policy engine | `AlarmCommandProcessor.process` (authorize before apply) | `AlarmCommandProcessorTests.testRejectedCommandMutatesNothing` |
| 4 | LLM produces only proposals | `AlarmProposal` / `ValidatedAlarmIntent` (create-only, no command) | `DefaultAlarmPolicyEngineTests.testAgentCannotSuppressCriticalAlarmEvenConfirmed` |
| 5 | Proposal not executable without validation + policy | `AgentOrchestrator` (only handoff, via boundary) | `AgentOrchestratorTests`, `CommandProposalAuditTests` |
| 6 | Critical alarms need explicit confirmation | `DefaultAlarmPolicyEngine` (re-reads real criticality) | `DefaultAlarmPolicyEngineTests` (cancel/weaken/snooze/delete) |
| 7 | No response ⇒ no mutation | `AlarmCommandProcessor` keepOriginal no-op | `PreAlarmKeepOriginalTests` |
| 8 | Movement inference never cancels | `PreAlarmEvaluator` (no command) | `PreAlarmEvaluatorTests` |
| 9 | Background never required to ring | `PreAlarmBackgroundRunner` (no authority) | `BackgroundSchedulingTests.testBackgroundRunnerHoldsNoAlarmAuthority` |
| 10 | Crash/failure preserves last safe alarm | `AlarmCommandProcessor` (persist-first, outbox, uncertain) | `BackgroundExpirationTerminationTests`, `CorruptionRecoveryTests`, `AlarmReconciliationTests` |
| 11 | Store IANA zones | `IANATimeZone` | `AlarmDomainTests`, `IANATimeZoneTests` |
| 12 | Wall-clock vs fixed-instant intent | `ScheduleRule` (weekly/oneTime) | `AlarmSchedulingEngineTests` |
| 13 | Recompute via a pure engine | `AlarmSchedulingEngine.nextOccurrence` | `AlarmSchedulingEngineTests`, `PerformanceTests` |
| 14 | DST ambiguous/nonexistent handled | `AlarmSchedulingEngine` | `AlarmSchedulingEngineTests` (DST cases) |
| 15 | Date-line no dup/skip | `AlarmSchedulingEngine` | `AlarmSchedulingDateLineTests` |
| 16 | Location can't silently change critical | `AlarmReconciler` (criticality divergence) | `AlarmReconcilerTests.testDivergentCriticalityIsRescheduled` |
| 17 | Cached location timestamp-validated | `TravelDomain` significant-location freshness | `SignificantLocationTests` |
| 18 | Challenge starts only after explicit interaction | `WakeChallengeMachine` (`.start` only) | `WakeChallengeTests.testInvalidTransitionsAreNoOps` |
| 19 | Pass requires multiple independent signals | `WalkVerifier`/`CadenceRegularity`/`DeviceMotionEvidence` | unit tests — **P1: not wired to the pass path** (see Findings) |
| 20 | Shaking alone cannot pass | `CadenceRegularity` (anti-shake) | **P1: gate not composed; see Findings / WG-243** |
| 21 | Sensor unavailability can't trap the user | `WakeChallengePhase.unavailable` (non-dismissing) | `WakeChallengeTests`, `ChallengeStopTests` |
| 22 | Accessible alternative | `AccessibleChallengeMachine` | `AccessibleChallengeTests`, `SoakTests` |
| 23 | Challenge state survives UI transitions | value-type machine in `@Observable` VM | `SoakTests` (indirect; explicit scenePhase test — P3) |
| 24 | Stop only on valid terminal pass / fallback | `ChallengeStopCoordinator` | `ChallengeStopTests` |
| 25 | Disclose carrying the phone | create/challenge copy + review notes | localization/aesthetic scans |
| 26 | Constrained structured outputs | `AISchema` / `StructuredGenerator` | `StructuredGeneratorTests`, `AISchemaTests` |
| 27 | Reject unknown enums / out-of-range / bad IDs | `AISchema` fail-closed decode + `AlarmIntentValidator` | `AISchemaTests`, `AlarmIntentValidatorTests` |
| 28 | Untrusted calendar/journal text | `RedactedEventSummary`, `PromptSafety` | `HostileEventTextTests`, `PromptInjectionTests` |
| 29 | Untrusted content can't override policy | `PromptSafety` delimiting + policy independence | `PromptInjectionTests` |
| 30 | No general arbitrary-mutation tool | provider is generate-only; no tool surface | `LanguageModelProviderTests` |
| 31 | Policy engine assigns criticality, not the model | `DefaultAlarmPolicyEngine` | `DefaultAlarmPolicyEngineTests` |
| 32 | Explanations from recorded factors | `ExplanationGenerator` (drops ungrounded) | `ExplanationGeneratorTests` |
| 33 | Inadequate availability ⇒ deterministic fallback | `AIAvailabilityGate`, generator `.noProposal` | `AIAvailabilityGateTests`, `TomorrowProposalGeneratorTests` |
| 34 | Cloud opt-in + separately consented | `CloudProviderGate` (flag + consent, both off) | `CloudProviderTests` |
| 35 | No raw health/location/full-calendar to cloud | `CloudSafeText` (private init via `CloudRedactor`) | `CloudProviderTests`, `PromptInjectionTests` |
| 36 | Health optional | feature-gated | `ReadinessViewModelTests` |
| 37 | Request each permission in context | `OnboardingPlan` (feature-triggered) | `OnboardingTests` |
| 38 | Useful with permissions denied | degraded paths | `HealthAccessStatesTests`, `AIAvailabilityGateTests` |
| 39 | No medical claims | copy + `UrgentSymptomPolicy` | `WellnessSafetyCopyTests`, `ConsentCenterTests` |
| 40 | No advertising use | no ad SDK; copy | `ConsentCenterTests`, `PrivacyLeakScanTests` |
| 41 | No sensitive raw logging | `PrivacyLog` redaction; source-scans | `PrivacyLeakScanTests`, `StructuredGeneratorTests` |
| 42 | Export & deletion controls | `ExportBuilder`, `LocalDataDeletion` | `ExportTests`, `DeletionTests` |
| 43 | Explicit configurable retention | `RetentionPolicy` | `RetentionTests` |
| 44 | Coarse non-sensitive analytics | `AnalyticsEvent` (closed schema) | `AnalyticsTests` |
| 45 | Third-party SDK privacy review | none shipped; SDK inventory | `PrivacyLeakScanTests`, `docs/SDK_INVENTORY.md` |
| 46 | Actor on every mutation | `AlarmCommandProcessor` audit append | `AlarmReconciliationTests`, `AgentOrchestratorTests` — **P2: best-effort `try?`** |
| 47 | Old/new state, reason, ts, correlationID, outcome | `AuditEvent` | `AlarmCommandProcessorTests`, `CommandProposalAuditTests` |
| 48 | Append-only in normal operation | `AuditRepository` (no update/delete) | `CoreDataAuditRepositoryTests` |
| 49 | User-understandable history | `AlarmHistoryViewModel` | `AlarmHistoryViewModelTests` |
| 50 | Recovery distinguishable | `AuditEvent.isRecovery` / `.systemReconciliation` | `CommandProposalAuditTests` — **P2: dead `.recovery` actor** |

## Findings (tracked blocking issues)

- **P1 — #19/#20 anti-shake gate not composed.** `CadenceRegularity`/`WalkVerifier` are complete and
  unit-tested but invoked by **no runtime pass path**; `WakeChallengeMachine.apply(.observedProgress)`
  passes on cumulative step count alone, and there is no end-to-end "a shake cannot stop the alarm" test.
  Not P0 because the walk challenge is not yet composed into the running app (no production path constructs
  `observedProgress` or presents `ChallengeView`), so no shipping surface is defeatable today — but it
  **blocks enabling the walk challenge**. **Owner: WG-243 (motion red team)** — gate the pass on multi-signal
  corroboration + add the regression test.
- **P2 — #46 audit is best-effort.** `AlarmCommandProcessor` appends the audit with `try?` after the alarm
  save, so a save-succeeds/audit-fails window can drop the actor record. Track a launch-time state-vs-audit
  backfill or a transactional audit; low likelihood, on-device only.
- **P2 — #50 dead `.recovery` path.** `AuditActor.recovery` / `AlarmCommand.recover` are never emitted;
  corruption recovery folds into `.systemReconciliation`. Either wire the distinct marker or delete the dead
  cases and document that recovery == reconciliation.
- **P2 — dead outbox recovery API.** `Repositories.unresolvedEntries()/pendingEntries()` have no production
  consumer (ground-truth reconciliation supersedes outbox replay). Remove or wire, and document the choice.

No feature work proceeds with an open **P0**; there is none. The P1 blocks the walk-challenge feature and is
assigned to WG-243.
