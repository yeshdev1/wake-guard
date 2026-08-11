# WakeGuard — Testability Report

Scope: what can be verified, where, and how — across automated tests, the iOS Simulator, and a physical
device. Written for QA to plan coverage and to know which claims require a device.

Build under test: branch `yeshdev1/wakeguard-parent-bootstrap`. Automated gate: **1240 tests, 0 failures,
0 warnings**, SwiftLint `--strict` clean, swift-format clean (`make ci-fast`).

---

## 1. The three test tiers

| Tier | What it proves | How to run | In CI? |
|---|---|---|---|
| **Automated** (unit + integration + source-scan) | Deterministic logic, composition wiring, safety invariants, privacy pins, perf bounds | `make ci-fast` (~15 s after build) | Yes |
| **Simulator** (smoke + UI flows) | The app launches, screens are reachable/navigable, no crashes, degraded paths render | `make test-ui`; or launch in Xcode/`simctl` | UI tests: on demand |
| **Device** (WG-030 real-device matrix) | Alarms actually **ring**, real sensors, real HealthKit/AI, signed upload | Manual, on hardware | No — manual |

### What "automated" covers (1240 tests)
- **Domain logic** — scheduling/DST/date-line, reconciliation, policy authorization, anti-shake corroboration, redaction, retention math. Pure + deterministic (injected `Clock`/ids).
- **Integration** — real Core Data (in-memory store): repositories, the command processor, the data eraser, retention job.
- **Composition wiring (this effort)** — every newly-wired subsystem has a test:
  - `CoreDataDataEraserTests`, `RetentionCleanupJobTests`, `AppEnvironmentTests` (privacy controls reachable) — Phase A
  - `SystemTimeZoneMonitorTests` — Phase B
  - `DiagnosticsWiringTests` — Phase C
  - `WakeChallengeRuntimeTests`, `ChallengeStopTests` — Phase D
  - `SettingsRepositoryContractTests` (onboarding flag), `ConversationalAlarmBuilderTests`, `ReadinessWiringTests`, `ConsentStatusMappingTests` — Phase E
- **Safety-invariant pins** — source-scan tests that fail the build if an invariant is broken (`PrivacyLeakScanTests`, `LocationPrivacyGuardTests`, `SecretHandlingAuditTests`, `PromptInjectionDefenseTests`, `InvariantMapTests`, `ReleaseReadinessTests`, `ReduceMotionTests`, `RTLLayoutTests`, `NonColorStatusTests`, `DynamicTypeLayoutTests`, `AestheticConsistencyTests`).
- **Perf bounds** — `PerformanceTests` (reconcile 2,000 rules < 2 s; `nextOccurrence` hot path).

### What the **simulator** adds
- Launch of the **production composition root** without crashing (verified).
- Navigation/reachability of every wired screen (see UAT).
- Degraded paths that render honestly with no hardware: readiness "not enough data", the walk challenge falling back to the accessible alternative, conversational create failing closed to the manual editor.
- **Not** covered by the sim: real ringing, real sensor data, real on-device AI.

### What requires a **device** (cannot be faked — WG-030)
- **Alarms ringing** through silent mode / Focus (the composed `DeferredAlarmManagerAdapter` rings nothing off-device; real AlarmKit needs a device + the entitlement).
- The **unattended ring → challenge** hookup (device-only AlarmKit alerting observation).
- **Real sensors**: a genuine walk through the pedometer, HealthKit sleep, CoreLocation travel.
- **On-device AI** (FoundationModels) for the conversational parse.
- **Battery/latency** absolute numbers, cold-launch time, and the AlarmKit launch **notification-permission prompt** timing.
- **Signed archive + TestFlight upload** (WG-260 — needs Apple credentials).

---

## 2. Coverage by feature area

| Area | Automated | Simulator | Device-only |
|---|---|---|---|
| Create / edit / enable / disable / delete alarm | ✓ (view-model + processor) | ✓ (flows) | ring |
| Critical-alarm confirmation gating (#6) | ✓ (`DefaultAlarmPolicyEngineTests`, incl. "ring" copy) | ✓ (dialog) | ring |
| Reconciliation / lost-update guard (#10) | ✓ (`AlarmReconciliationTests`) | partial | AlarmKit sync |
| Time-zone travel correction (#12–#16) | ✓ (detector + monitor launch) | — | live `NSSystemTimeZoneDidChange` |
| Privacy: export / delete / retention / consent (#42/#43) | ✓ | ✓ (navigate + run) | — |
| Diagnostics (#230) | ✓ | ✓ | — |
| Walk challenge #18–#24 | ✓ (runtime pipeline) | ✓ ("Test challenge" → accessible fallback) | real walk + real ring |
| Onboarding | ✓ (persist flag) | ✓ (first-launch) | — |
| Conversational AI create | ✓ (converter + fail-closed + scripted E2E) | ✓ (fail-closed to manual) | real NL parse |
| Readiness | ✓ (degrades safely) | ✓ (degraded card + Health prompt) | real sleep data |
| Privacy leak / secrets / injection | ✓ (source-scan pins) | — | — |

---

## 3. Known automated-coverage gaps (for QA awareness)

- **UI reachability is not in `ci-fast`** — the new screens have accessibility identifiers (`privacySettingsButton`, `readinessButton`, `describeAlarmButton`, `testChallenge`, `challengeHost`, `privacyLink*`, `diagnosticsReport`, `conversational*`), but an end-to-end navigation UITest across them is a follow-up (`make test-ui` covers the pre-existing create/edit/delete/critical/travel flows). QA should navigate them manually (UAT §Composition).
- **The AlarmKit launch notification prompt** is framework behavior; its exact timing is device-only.
- **`recentErrors` in Diagnostics** is currently always empty (the redacted crash-breadcrumb buffer is a tracked follow-up) — expect an empty "Recent errors" section.
- **`eraseOptional` categories** (journal/recommendations/motion/health-derived) are documented no-ops today (nothing is persisted for them) — deleting them reports success because there is nothing on disk to remove.

---

## 4. How to run each tier

```
make ci-fast          # automated gate: build + lint + format + full test suite (0 warnings required)
make test-ui          # simulator UI flows (pre-existing create/edit/delete/critical/travel)
make test-fast ONLY=WakeGuardTests/<TestName>   # a single test class, fast
# Simulator smoke launch (production graph):
xcodebuild build -project WakeGuard.xcodeproj -scheme WakeGuard \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath build/smoke
xcrun simctl install booted build/smoke/Build/Products/Debug-iphonesimulator/WakeGuard.app
xcrun simctl launch booted com.wakeguard.app
```

Device build/upload: `make archive` → `make export` → upload (needs Apple credentials — see
`docs/RELEASE_PIPELINE.md`).
