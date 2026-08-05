# Architecture Decision Record Index

Record each decision as:

```text
## ADR-XXX: Title
Status:
Date:
Context:
Decision:
Alternatives considered:
Consequences:
Safety/privacy impact:
Revisit trigger:
```

Decision index (Accepted decisions are recorded in full below; WG-002 covers
ADR-001 through ADR-004):

- ADR-001: iOS deployment target — **Accepted** (see below).
- ADR-002: Persistence — Core Data primary, SwiftData deferred — **Accepted** (see below).
- ADR-003: single target versus local Swift packages — **Accepted** (see below).
- ADR-004: on-device MVP AI versus optional cloud provider — **Accepted** (see below).
- ADR-005: default ten-second walk thresholds — pending.
- ADR-006: accessible challenge alternatives — pending.
- ADR-007: critical alarm definition — pending (unscheduled; see Assumptions log).
- ADR-008: pre-alarm evaluation windows — pending.
- ADR-009: audit retention — pending.
- ADR-010: analytics provider or no analytics — pending.

## ADR-001: iOS deployment target — iOS 26+

Status: Accepted
Date: 2026-08-01
Context: The core dependable-alarm capability depends on AlarmKit, the system
alarm authority (`SAFETY_INVARIANTS.md` #1), available from iOS 26.
`../START_HERE.md` recommends iOS 26+. Supporting older iOS would require a
non-AlarmKit fallback for critical alarms (local/push notifications) that cannot
guarantee ringing on a locked or silenced device, forking the most
safety-critical path.
Decision: Minimum deployment target is **iOS 26.0**. No back-deployment or
fallback-OS support in the MVP.
Alternatives considered:
- iOS 18–25 with `UNUserNotificationCenter` "alarms" as a fallback — rejected:
  notification-based alarms do not meet the dependable-ring promise, and two
  alarm engines multiply the safety surface.
- iOS 26+ with degradation on future betas — unnecessary at MVP.
Consequences: Can rely on AlarmKit, Core Data, Swift 6 concurrency, and on-device
Foundation Models where available (the availability fallback is specified in
ADR-004). Smaller initial device base
(acceptable for a safety-first MVP). CI/test matrix targets iOS 26
(`TEST_STRATEGY.md`).
Safety/privacy impact: Positive — a single, system-authoritative alarm path
reduces silent-failure risk versus a notification fallback. No privacy impact.
Revisit trigger: Material demand for < iOS 26, or a change in AlarmKit
availability/behavior — revisit before broadening OS support.

## ADR-002: Persistence — Core Data primary, SwiftData deferred

Status: Accepted (human-ratified 2026-08-01)
Date: 2026-08-01
Context: `ARCHITECTURE.md` §5 requires versioned schemas, migrations tested from
every shipped version, an outbox for pending AlarmKit operations, append-only
audit events, and background/launch-time reconciliation — all behind repository
protocols (WG-012) so the domain stays framework-independent. Target is iOS 26+.
The store is safety-critical: invariant #10 requires the last safe alarm to
survive crashes and failures. Because the domain is protocol-isolated, a store's
authoring ergonomics stay confined to the infrastructure layer, while its
migration and concurrency behavior sit directly on the safety path.
Decision: Use **Core Data** (`NSPersistentContainer` over SQLite) as the primary
store, accessed only through the repository protocols — chosen for proven,
inspectable migration tooling, `NSPersistentHistoryTracking` (well-suited to the
outbox + launch-time reconciliation pattern), explicit background-context
concurrency, and store-level file protection. **SwiftData is the documented
alternative**, deferred (see revisit trigger); it may be adopted later for a new
non-safety-critical store, or wholesale, once it demonstrably clears the WG-013
gates below.
Alternatives considered:
- SwiftData primary — less boilerplate and native Swift 6 ergonomics, and it is
  Core Data underneath; but its heavyweight-migration and Swift 6
  background-concurrency maturity are the open risks, and they land on the
  safety-critical path. The ergonomics win is contained by the repository
  boundary, so it does not offset the migration/reconciliation risk for the MVP.
- SQLite/GRDB directly — maximal control/testability, but hand-rolled
  schema/migration is more to get wrong for a small team; rejected for MVP.
Consequences: More boilerplate (managed-object codegen, mapping models) — but
confined to `AlarmInfrastructure`, not the domain. Gains mature migrations,
cross-launch history tracking for reconciliation, `newBackgroundContext` with
`NSManagedObjectID` hand-off for background writes, and `NSFileProtectionComplete`
on the alarm/audit store. WG-013 (Select and configure persistence) still
validates the three gates below as acceptance tests for the Core Data
implementation; they are store-agnostic and worth proving regardless.
Safety/privacy impact: Positive — proven migration and history/reconciliation
tooling reduces the risk of losing a scheduled alarm (invariant #10) versus a
less-mature store. On-device only; secrets in Keychain, not the store; the store
file is protected at rest.
WG-013 validation gates (acceptance tests for the persistence implementation):
1. **Migration gate** — a test migrates a v1 store (alarms + outbox rows + audit
   events) to v2 via a lightweight/inferred change **and** v2→v3 via a heavyweight
   mapping-model / `NSEntityMigrationPolicy` stage, asserting zero row loss and
   preserved append-only audit ordering.
2. **Background-write gate** — a background context write runs concurrent with a
   main-context read under Swift 6 strict concurrency, TSan clean, passing only
   `NSManagedObjectID` across isolation boundaries, with no `@unchecked Sendable`
   escape hatch in the repository.
3. **Outbox gate** — enqueue-outbox-row and update-alarm-state commit in a single
   `context.save()` (one local transaction), each row carries an idempotency key,
   and a crash between local commit and the AlarmKit call is repaired by
   reconciliation (there is no cross-store two-phase commit with AlarmKit;
   `ARCHITECTURE.md` §6).
Revisit trigger: reconsider SwiftData (for a new non-critical store, or a
wholesale migration) when it can demonstrably clear all three gates above in a
throwaway spike on the shipping iOS version **and** Core Data's boilerplate or
maintenance cost has become materially painful — via an ADR amendment, never
silently.

## ADR-003: Modularization — single target now, extract packages later

Status: Accepted
Date: 2026-08-01
Context: `ARCHITECTURE.md` §2 lists ~17 logical modules and states a
feature-folder structure inside one target is acceptable initially, provided
boundaries are enforced by protocols and tests; the domain must not import Apple
frameworks (§1).
Decision: Start as a **single app target** organized by feature folders that
mirror the module list, with layer boundaries enforced by protocols and tests.
**Extract stable seams into local Swift packages** (pure domain + `TestSupport`
first) once boundaries stabilize or build/test times warrant.
Alternatives considered:
- Multi-package from day one — strongest, compiler-checked boundaries, but heavy
  iteration cost while the design is still moving; premature for the foundation.
- Single target, folders only, no extraction plan — risks boundary erosion;
  mitigated here by protocol/test enforcement plus an explicit extraction
  trigger.
Consequences: Fast iteration now; a later package extraction is mechanical
because dependencies already flow through protocols. Needs a lightweight
lint/test guard (WG-004/WG-007) to catch domain→framework imports until the
domain is its own package.
Safety/privacy impact: Neutral. Enforced domain purity keeps deterministic
policy/scheduling logic testable and framework-independent, indirectly
supporting the invariants.
Revisit trigger: (1) any domain→Apple-framework import (`AlarmKit`, `CoreMotion`,
`CoreLocation`, `HealthKit`, `EventKit`, `UserNotifications`, `FoundationModels`)
under the domain path — the CI lint rule added in WG-004 must fail the build on
this; or (2) clean build exceeds an agreed threshold (placeholder: 3 min) or
incremental exceeds ~10 s, the numbers to be ratified in WG-004. On (1) or (2),
extract the pure domain and `TestSupport` into local packages first.

## ADR-004: MVP AI provider — on-device only

Status: Accepted
Date: 2026-08-01
Context: `PRODUCT_SPEC.md` §3.7 and `ARCHITECTURE.md` §8 make AI advisory only,
behind a `LanguageModelProvider` protocol, with structured/validated output
routed through `AlarmPolicyEngine`. `SAFETY_INVARIANTS.md` #34/#35 require cloud
processing to be opt-in, separately consented, and never sent raw
HealthKit/precise-location/full-calendar by default. `SCOPE.md` §4 (frozen)
places cloud AI processing out of MVP scope.
Decision: MVP ships **on-device only**, using Apple Foundation Models where
available, behind `LanguageModelProvider`, with a deterministic fake provider for
tests and a deterministic UI fallback when the model is unavailable or
low-confidence (#33). **No cloud model provider in the MVP**; an opt-in cloud
provider is deferred post-MVP behind explicit, separate consent.
Alternatives considered:
- Optional cloud provider in MVP behind opt-in — rejected for MVP: adds consent,
  data-minimization, redaction, and privacy-review surface (#35, #45) not
  justified before the deterministic core and on-device path are proven, and it
  is outside the frozen scope.
- No AI at all in MVP — rejected: on-device advisory features are a core
  differentiator and are safe under the policy-gated architecture.
Consequences: Provider protocol + fake enable deterministic tests now; on-device
keeps data on device (data minimization). Feature availability varies by device
capability, so a deterministic UI fallback is required everywhere (#33). Adding
cloud later is a new provider behind the same protocol plus a kill switch
(`ARCHITECTURE.md` §10), its own privacy review, and an ADR.
Safety/privacy impact: Strongly positive — no sensitive payloads leave the device
by default; AI cannot reach AlarmKit/persistence and only emits validated
`AlarmProposal`s (#4/#5/#26/#27/#30). Reinforces #34/#35.
Revisit trigger: (1) a committed, separately-consented cloud feature is scoped
(requires a scope-change ADR + human approval per `SCOPE.md` §5); or (2)
on-device model quality proves insufficient as measured against a fixed on-device
eval set for natural-language alarm setup and explanation faithfulness (#32),
with a pass threshold defined in the on-device AI tasks (epoch E09).

## Assumptions log

Material assumptions recorded per `CLAUDE.md`. These are not ADRs; formal
decisions are recorded above using the ADR template.

### WG-001 (2026-08-01): Scope and terminology freeze

- MVP scope and shared vocabulary are frozen in a dedicated `docs/SCOPE.md`
  rather than inline in `PRODUCT_SPEC.md`, so scope/terminology change control
  has one authoritative home. `PRODUCT_SPEC.md` remains the product detail.
- The **operational** definition of "critical alarm" (which categories default
  to critical, snooze/challenge constraints, thresholds) is intentionally
  deferred to **ADR-007**, which is indexed in this file's ADR list but not yet
  scheduled to a task (WG-002 owns ADR-001/002/003/004 only). WG-001 fixes only
  the term and its non-negotiable safety semantics, to avoid pre-empting the ADR.
- No automated test suite exists yet (no Xcode/SwiftPM target until WG-003;
  test-support module is WG-007). WG-001 is a documentation-only change, so its
  acceptance is verified by inspection; the "full available suite" is currently
  empty (0 tests). No test harness was introduced here to avoid broadening scope
  into WG-003/WG-004/WG-005/WG-007.
- `SCOPE.md` was intentionally **not** added to the `CLAUDE.md` always-read list
  in this task (editing `CLAUDE.md` would broaden scope). Recommended as a small
  follow-up.
- **Stricter-than-source terminology (intentional).** `SCOPE.md` §2 deliberately
  strengthens a few source statements: the "critical alarm" entry adds the verb
  "suppressed" to invariant #6's prohibitions and bans AI *inference* of
  criticality (beyond #31's wording), and §4 broadens the advertising exclusion
  to match #40 (adds location + calendar). These tighten safety and never weaken
  an invariant, so no ADR is required; recorded here so the deviations are not
  silent.
- **`AlarmManagerAdapter` naming reconciliation (follow-up).** `SAFETY_INVARIANTS.md`
  #1–#2 name `AlarmManagerAdapter` as the sole AlarmKit caller, but
  `ARCHITECTURE.md` §4 does not list that identifier. `SCOPE.md` §2.5 now defines
  it; reconciling the name into `ARCHITECTURE.md` is left as a small follow-up
  (candidate: WG-002 or the alarm-infrastructure tasks WG-024/027/028).

### WG-001 adversarial review (2026-08-01)

- A 3-round, 6-lens multi-agent adversarial review (safety-conflict,
  internal-consistency, correctness-vs-source, completeness, exploitability
  red-team, quality/clarity) with 3-skeptic majority verification confirmed **no
  safety-invariant weakening** and surfaced **7 unique docs-accuracy defects**
  (wrong invariant citations on `AlarmProposal`/DST/wake-challenge; a dropped
  circadian-suggestion capability; undefined cloud-AI MVP status; an undefined
  §2 change-control gate; overstated glossary count). All were fixed in the same
  pass. Report: `docs/reviews/2026-08-01-wg001-scope-terminology.md`.

### WG-002 (2026-08-01): Initial platform ADRs

- WG-002 records **decisions**, not implementation. ADR-002 selects **Core Data**
  as primary (SwiftData deferred); the actual configuration, migration plan, and
  outbox/audit proof are **WG-013**, which validates the three acceptance gates
  stated in ADR-002. No persistence code is written here.
- ADR-003 defers package extraction; **no Swift packages are created in WG-002**
  (structural setup is WG-003). Boundaries are enforced by protocols + tests +
  review until an extraction trigger fires.
- WG-002 did **not** edit `ARCHITECTURE.md` to reconcile the `AlarmManagerAdapter`
  naming gap noted under WG-001; that is a documentation follow-up left to the
  alarm-infrastructure tasks (WG-024/027/028) and is out of WG-002's
  "platform decisions" scope.
- ADR-001/003/004 restate and formalize existing project direction
  (`../START_HERE.md`, `ARCHITECTURE.md`, frozen `SCOPE.md`); ADR-002 is the one
  genuinely new commitment and the most consequential — the repo owner ratified
  **Core Data-primary** on 2026-08-01 after weighing it against SwiftData-primary
  (migration maturity, history-tracking reconciliation, and background-write
  safety on the #10 path outweighed SwiftData's ergonomics, which the repository
  boundary already contains). Remains cheaply amendable behind the protocols.
- No automated suite exists yet (docs-only; build target is WG-003). Acceptance
  verified by inspection; available suite = 0 tests.

### WG-003 (2026-08-01): Repository structure and Xcode project

- **Project generation via XcodeGen.** `project.yml` is the source of truth; the
  generated `WakeGuard.xcodeproj` is git-ignored. "Builds on a clean machine" =
  `brew install xcodegen && make test`. Rationale: a reviewable, diffable project
  definition with no `project.pbxproj` merge churn. XcodeGen is a build-time dev
  tool (MIT), not linked into the shipped app, so CLAUDE.md's third-party-SDK
  review bar applies only lightly; the CI task (WG-005) will pin/install it.
- **Single app target, feature folders (ADR-003).** `Sources/` holds one folder
  per `ARCHITECTURE.md` §2 module (16 folders incl. `WakeGuardApp`); each
  non-app module is an empty `enum` namespace marker until its task adds real
  types. `TestSupport` lives under `Tests/` and is empty until WG-007.
- **Warning/lint policy deferred to WG-004.** WG-003 sets Swift 6 language mode
  and `SWIFT_STRICT_CONCURRENCY=complete` only; it does **not** turn on
  warnings-as-errors (that policy is WG-004's, to avoid scope overlap and a
  fragile first build).
- **No product logic.** No domain, persistence/Core Data, or AlarmKit code
  (those are WG-010/WG-012/WG-013). The `@main` entry point composes only the
  placeholder root view — no business logic (acceptance criterion).
- `Info.plist` is synthesized (`GENERATE_INFOPLIST_FILE=YES`); no hand-written
  plist. `README.md` updated with the build/bootstrap instructions.

### WG-004 (2026-08-01): Formatting, linting, and warning policy

- **Formatter: Apple `swift-format`** (bundled in the Swift 6 toolchain), config
  `.swift-format` — chosen over nicklockwood/SwiftFormat to avoid an extra
  dependency. Import ordering is owned by swift-format (`OrderedImports`);
  swiftlint's `sorted_imports` is intentionally left off so the two tools never
  disagree.
- **Linter: SwiftLint `--strict`**, config `.swiftlint.yml`.
  `force_unwrapping` / `force_try` / `force_cast` escalated to **error** per
  CLAUDE.md. A custom **`domain_no_apple_frameworks`** rule enforces ADR-003
  domain purity — **verified** to error on an Apple-framework import inside a
  `*Domain/` file and to stay silent for the same import in an Infrastructure
  file. This is the compiler-independent guard ADR-003's revisit trigger
  promised, closing the WG-003 review's L1 gap.
- **Warnings-as-errors is global:** `SWIFT_TREAT_WARNINGS_AS_ERRORS` +
  `GCC_TREAT_WARNINGS_AS_ERRORS` in `project.yml`, so **both** local and CI
  builds fail on warnings (satisfies "CI fails on agreed warnings" and CLAUDE.md,
  not CI-only). The scaffold builds clean under it (0 warnings).
- **SwiftLint is not an Xcode build phase** — kept out of the compile to avoid
  coupling/slowness; it runs via `make lint` / `make ci`, which WG-005's CI job
  will invoke. Generated/build artifacts are excluded (`.swiftlint.yml
  excluded:`; the `.xcodeproj` is already git-ignored).
- `swiftlint` and `swift-format` are dev tools (not shipped SDKs), so CLAUDE.md's
  third-party-SDK bar applies lightly; `README.md` documents every command.
- **Adversarial-review refinements (ios-architect).** The domain-purity guard was
  hardened after review: the regex now also catches submodule/kind imports
  (`import struct CoreLocation.CLLocation`), attributed imports (`@_exported`,
  `@preconcurrency`), and a companion rule catches `canImport(...)`. Scope widened
  from the four `*Domain` modules to also cover `AlarmApplication`/`AIApplication`
  (use cases orchestrate via ports; an `AIApplication` framework import would
  breach `SAFETY_INVARIANTS.md` #1/#30). All six forms were verified to fail the
  lint and then revert clean.
- **Force-unwrap is an error in tests too** — intentionally stricter than
  CLAUDE.md's "production paths" wording. Tests use `XCTUnwrap`, not `!`. Chosen
  for a safety-critical codebase and documented here + in `README.md` so it is not
  a silent surprise when WG-007 adds the test-support module.
- **Warnings-as-errors tradeoff (accepted).** A future iOS SDK deprecation warning
  will break the build **locally**, not only in CI. Accepted per CLAUDE.md
  ("warnings are failures unless documented"); such a case gets a documented,
  narrowly scoped exception rather than disabling the policy.

### WG-005 (2026-08-01): CI build and unit-test workflow

- **GitHub Actions** (`.github/workflows/ci.yml`) on push-to-`main` + PR +
  `workflow_dispatch`. **CI reuses the `make` targets** (`lint`, `format-check`,
  `test`) so the CI gate is identical to the local one (DRY, no drift). Added an
  optional `RESULT_BUNDLE` var to the Makefile `test` target for the artifact.
- **No secrets** (`permissions: contents: read`; public tooling only) — satisfies
  "secrets are not required for basic CI". Only first-party actions are used
  (`actions/checkout@v4`, `actions/upload-artifact@v4`); the third-party
  setup-xcode action was **avoided** to keep the dependency surface minimal.
- **Runner adaptivity:** `runs-on: macos-latest`; the workflow selects the newest
  installed Xcode (`/Applications/Xcode_*.app`) and the newest available iPhone
  simulator dynamically (no OS pin), so it adapts to whatever the runner image
  provides. **Assumption:** the runner supplies Xcode 26 / the iOS 26 SDK. If a
  future `macos-latest` lacks it, pin a concrete image or Xcode version.
- **Artifacts:** `TestResults.xcresult` uploaded (14-day retention, `if: always()`)
  so results are retained even on failure — satisfies "artifacts retain test
  results".
- **Verification limits:** GitHub Actions cannot run locally (no `act` installed).
  Validated **statically** with `actionlint` (clean, incl. embedded shellcheck)
  and by running the **exact command sequence** locally (`make lint` +
  `format-check` + `test RESULT_BUNDLE=…`) → green, `.xcresult` produced.
- **Adversarial review (release-test-engineer) applied:** the setup step now
  asserts the **iOS 26 SDK** and `swift format` are present (fail loud rather than
  build green on the wrong SDK), hard-fails when no iPhone simulator is available
  (no guessed fallback), runs `make clean` before building, and calls **`make ci`
  directly** so the CI and local gates cannot drift; `main` runs are never
  cancelled. **Accepted follow-ups (non-blocking):** pin the runner image/Xcode
  and SHA-pin **and bump** the two first-party actions (+ Dependabot) before CI
  ever gains a secret or a deploy step — blast radius today is nil (read-only, no
  secrets). The first green run (GitHub Actions run 30710911477, 3m20s) flagged
  GitHub's Node20 runtime deprecation for `checkout@v4`/`upload-artifact@v4`
  (auto-forced to Node24 — non-fatal), which the bump will resolve.

### WG-006 (2026-08-01): Implementation status and task tracking

- **Restructured `IMPLEMENTATION_STATUS.md`** into: a policy/legend, a generated
  **Task index** (all 176 backlog tasks — status, `_unassigned_` owner placeholder,
  evidence link) between generator markers, and the **Detailed evidence log**
  (rich narrative for active/done tasks). The index is authoritative for
  status/owner/evidence; the structural columns (Title/Epoch/Depends) are derived
  from `BACKLOG.md` and cannot drift (enforced — see below).
- **`scripts/task_tracking.py`** (stdlib-only Python) `--generate`s the index
  (preserving human-set state) and `--check` enforces: every backlog task is
  tracked, no orphan rows, valid statuses, **evidence-on-status-change** (an
  In progress/In review/Complete task must carry a real evidence link — markdown
  link, URL, commit hash, or `run <n>`), and no structural drift (byte-exact vs a
  fresh generation). Wired into `make ci` as the fail-fast first step, so CI
  enforces tracking on every push; macOS runners ship `python3`.
- **Owner is a placeholder (`_unassigned_`).** The acceptance asks for an owner
  placeholder, not assignment; owners are assigned later.
- The Python dev-tool dependency is acceptable per CLAUDE.md (stdlib-only, not
  shipped in the app; not a third-party SDK).
- `release-test-engineer` review hardened the checker (H1: evidence must *look
  like* a link, not merely be non-blank; H2: `--check` now catches structural
  drift, not just presence; M1: duplicate-marker guard; N1: robust dependency
  scan) — all verified by fault injection.

### WG-007 (2026-08-02): Deterministic test-support module

- **Delivered in `Tests/TestSupport/`** (compiled into the test target):
  `WallClock` + `TestClock` (a wall-clock that only moves when moved),
  `IdentifierGenerator` + `DeterministicIDGenerator` (reproducible seeded UUIDs),
  a generic `InMemoryRepository<Element>` (insertion-ordered), and a
  `Synchronized` (`Mutex`-backed) helper.
- **Scope boundary — no domain-dependent fakes.** `FakeAlarmManager`,
  `FakePedometer`, `FakeLanguageModelProvider`, the alarm-specific
  `InMemoryAlarmRepository`, etc. need protocols that do not exist yet
  (WG-010/012/024/060/AIInfrastructure) and are built with those tasks. The
  generic `InMemoryRepository` satisfies "in-memory repository compiles"; the
  alarm repository is WG-014.
- **Ports live in TestSupport for now.** `WallClock` / `IdentifierGenerator` are
  defined beside their fakes because no production code consumes them yet; they
  are promoted to a production port module when production first needs them
  (WG-018 container / WG-020 scheduling), per ADR-003. Defining production ports
  now would pre-empt WG-010/012/018.
- **`WallClock`, not `Clock`.** Named to avoid overloading the stdlib's
  duration-based `Swift.Clock` (a module-level `Clock` compiles but is a
  readability/inference footgun for WG-020+). `WallClock` also names the
  semantics precisely (`now: Date`). This realizes CLAUDE.md's "injected clock
  abstraction".
- **Swift 6 strict concurrency:** every double is `Sendable` via a `Mutex`
  (`Synchronization`) wrapped in `Synchronized`, whose `mutate` uses `sending`
  closures to satisfy region-based isolation — no `@unchecked Sendable`.
  Concurrency-stress tests (1,000 concurrent `next()`, 500 concurrent `upsert`)
  confirm no lost updates.
- **No force-unwrap** (WG-004): `DeterministicIDGenerator` packs UUIDs from a
  fixed 8-byte buffer; tests use optional chaining / `XCTAssertNil`. (The UUIDs
  are deterministic, not RFC-4122 v4 — fine for tests; noted for when the real
  generator is wired in WG-018.)

### WG-010 (2026-08-02): Alarm domain models

- **Entity models in `Sources/AlarmDomain/`** (Foundation-only, all `internal`):
  validated leaf value types (`TimeOfDay`, `CalendarDate`, `Weekday`/`WeekdaySet`,
  `IANATimeZone`), `ScheduleRule` (`.oneTime`/`.weekly`), the policies
  (`Criticality`, `AlarmSound`, `SnoozePolicy`, `PreAlarmPolicy`, `TravelBehavior`
  + `RegionRule`/`SafeFallback`, `ChallengePolicy` + `WalkChallenge`), and the
  `Alarm` aggregate (+ typed `AlarmID`). All `Codable`/`Sendable`/`Equatable`/
  `Hashable`.
- **Invalid states unrepresentable-or-validated at construction *and* decode.**
  Throwing initializers validate ranges/cross-field invariants; every validated
  type has a custom `Decodable` that re-runs the throwing init, so no Codable
  path bypasses validation (verified by the reviewer decoding adversarial JSON).
  Enabled-but-zero snooze/pre-alarm states normalize or throw.
- **`IANATimeZone` enforces #11.** Rejects the fixed-offset `GMT` family
  (`GMT`, `GMT+0`, `GMT±HHMM`) via an input `hasPrefix("GMT")` guard plus a
  canonical `GMT±` check (catches `UTC+5`); accepts `UTC`, named `Etc/*`, and all
  geographic zones. (`knownTimeZoneIdentifiers` was unusable — it has alias gaps
  like Calcutta-vs-Kolkata and omits UTC.)
- **`ScheduleRule` "local-time behavior" (ARCHITECTURE §3) is consolidated into
  the Alarm's `TravelBehavior`** (SCOPE §2.4), keeping the #12 wall-clock-vs-fixed
  *recurrence intent* separate from the travel *response* — one source of truth,
  not two.
- **Criticality is stored user data only** — the model never assigns or infers it
  (#31; the policy engine owns authorization, WG-028). `ChallengePolicy.walk`
  always carries an `accessibleFallback`, so SCOPE §2.3 holds by construction.
- **Known limitation (record before WG-020): identifier-based zone equality.**
  Foundation does not canonicalize IANA aliases, so
  `IANATimeZone("Asia/Calcutta") != IANATimeZone("Asia/Kolkata")` though they are
  the same zone. `IANATimeZone` stores the *input* identifier (round-trips
  cleanly). The reconciler/scheduler (WG-020+) must normalize before comparing or
  dedup-keying; there is no clean Foundation alias-canonicalizer, so
  canonicalization is deferred.
- **Deferred field validation (no safety impact):** `Alarm.label`,
  `AlarmSound.identifier`, and `RegionRule.regionIdentifier` accept empty strings
  (unlabeled alarms are valid; sound/region resolution are UI/infra concerns).
- **Scope:** no commands/proposals/audit (WG-011), no next-occurrence calculation
  (WG-020), no repository protocols (WG-012). `ios-architect` review (executed
  against the real SDK) found and I fixed a #11 blocker (bare-`GMT` hole) and
  added GMT-family + composite-decode-rejection tests.

### WG-011 (2026-08-02): Command, proposal, and audit models

- **Three distinct types in `Sources/AlarmDomain/`:** `AlarmCommand` (enum of the
  ten command kinds + an `alarmID` accessor, `Codable` for the outbox),
  `AlarmProposal` (advisory AI type carrying a `proposedCommand` + explanation /
  evidence refs / `ConfidenceBand` / expiry / provider), and `AuditEvent`
  (+ `AuditActor`/`CommandSource`/`Outcome` and `CorrelationID`/`AuditEventID`).
- **Fail-closed enums (#27):** `AuditActor`, `CommandSource`, `Outcome`,
  `ConfidenceBand`, and `EvidenceKind` are all `String`-raw, so decoding an
  unknown/forged value throws (verified for the composite `AuditEvent` too, via a
  tampered `"actor"`).
- **`AuditActor`, not `Actor`** — avoids overloading the concurrency `Actor`
  marker protocol (same lesson as `WallClock`).
- **AI-can-only-propose boundary (#4/#5):** `AlarmProposal` is a distinct,
  non-executable value; it merely *carries* a `proposedCommand`. The boundary is
  convention + domain-purity-lint enforced today (single target, ADR-003); it
  becomes a **compiler** wall only after package extraction. Handoffs recorded
  below.
- **Handoffs to downstream tasks (from the alarm-safety review):**
  - **WG-028/WG-161 must allow-list which `AlarmCommand` kinds a proposal may
    carry.** The model deliberately permits any kind (incl.
    `markChallengePassed`/`recover`/`reconcile`), per #31 (the model embeds no
    policy) — so the policy engine, not the type, must forbid an AI proposing
    e.g. `markChallengePassed` (which would defeat the challenge, #20/#24).
  - **Occurrence identity is `(AlarmID, fireTime: Date)`** — an absolute instant,
    which correctly distinguishes DST fall-back/spring-forward occurrences
    (verified). It carries **no `revision`**, so WG-027/WG-020 must reconcile a
    stale occurrence command (queued before a reschedule) by revision.
  - **A succeeded *mutation* audit must have non-nil old/new state hashes** —
    documented on the fields; WG-027/WG-015 enforce it (the model can't know which
    commands mutate). `AuditEvent` is an immutable value; append-only *storage* is
    WG-015's job.
  - `AlarmCommand`'s synthesized `Codable` tolerates extra payload keys (can't
    change the case identity); note for WG-016 if outbox rows ever cross a trust
    boundary.

### WG-020 (2026-08-02): Pure next-occurrence calculator

- **`AlarmSchedulingEngine`** (`Sources/AlarmDomain/`) is a pure, `Sendable`,
  stateless function of `(ScheduleRule, now: Date, timeZone: TimeZone) -> Date?`:
  no `Date()`, no ambient state. It computes the earliest occurrence **strictly
  after `now`** (`> now`); one-time returns `nil` if past; weekly is the earliest
  match across the weekday set. Foundation `Calendar` does the date math.
- **Injected zone, by design:** the engine interprets the rule's wall-clock in the
  **injected** `timeZone` and ignores `ScheduleRule.anchorTimeZone`. Selecting
  which zone to inject per `TravelBehavior` (device zone for follow-local, anchor
  zone for fixed) is **WG-021** — which must be the single choke point, since the
  engine cannot detect a caller passing the wrong zone for a fixed-zone critical
  alarm.
- **DST defaults chosen to never skip (alarm-safety review, SDK-verified):**
  weekly uses `matchingPolicy: .nextTime`, which resolves a nonexistent
  spring-forward wall-clock **forward** (02:30 → 03:00) rather than skipping a
  week (`.strict` would silently skip — a #10/#14 violation). Characterization
  tests pin this so a future policy change is caught. The **explicit** policy is
  WG-022.
- **Known DST edges handed to WG-022/WG-026/WG-029 (verified against the SDK):**
  - **Fall-back enumeration duplicate:** `nextOccurrence` itself returns a single
    earliest match (the earlier, EDT instant), so WG-020 does not duplicate. But
    any *enumeration* that feeds the prior result forward (WG-026 scheduling /
    WG-029 reconciliation) will get the repeated 01:30 EST instant next and fire
    **twice on the fall-back day** — those tasks must dedupe across the repeated
    hour (#14/#15).
  - **One-time vs weekly gap divergence:** the same nonexistent 02:30 resolves to
    **03:30 one-time** (`date(from:)`) but **03:00 weekly** (`nextDate(.nextTime)`)
    — a 30-min divergence WG-022 should converge deliberately. Both fire; neither
    skips.
  - **Fencepost:** `> now` (an occurrence exactly at `now` returns nil/next) is the
    safe "next" contract, but **WG-029 must treat "no future occurrence" as "leave
    the currently-firing alarm alone," never cancel** (AlarmKit is the ring
    authority, #1).
- **Scope:** WG-020 is the base calc only — zone selection (WG-021), explicit DST
  policy (WG-022), and date line / unusual offsets (WG-023) are separate tasks.

### WG-021 (2026-08-02): Wall-clock vs fixed-zone semantics

- **The single zone-selection choke point** (closing the WG-020 handoff):
  `AlarmSchedulingEngine.schedulingTimeZone(for:anchor:deviceTimeZone:)` maps
  `TravelBehavior` → the zone the base engine interprets the wall-clock in (#12):
  `followLocal` → device zone; `stayFixed` → anchor zone. `nextOccurrence(for:
  Alarm, after:, deviceTimeZone:)` composes it over WG-020.
- **`.askOnChange` and `.regionRule` default to the anchor zone** — the
  no-silent-shift choice (#16): until the user resolves an "ask" (or region logic
  runs), the schedule stays in its original zone; the alternative (device zone)
  would be exactly the silent shift #16 forbids. **When E06/WG-046 adds the
  interactive ask + live region resolution, it must route through this same
  function, not around it.** The `regionRule` branch currently always takes the
  `safeFallback` (region identifier is not consulted here — that's E06).
- **IANA anchor persists (#11):** follow-local only changes the *interpretation*
  zone; the stored `ScheduleRule.anchorTimeZone` identifier is never mutated
  (verified via Codable round-trip). Zone-only — no device *location* is read
  (#16).
- **`nextOccurrence(for: Alarm,...)` does not consult `isEnabled`** — a pure
  primitive; the caller (WG-026/WG-029) gates whether a disabled alarm is
  scheduled. Documented on the method.
- **Follow-local DST gaps** resolve in the **device** zone (inherited WG-020
  `.nextTime`/`date(from:)` behavior — forward, never skipped); the explicit
  policy is WG-022. No criticality/authorization logic here (#31).

### WG-012 (2026-08-02): Repository protocols

- **Four domain ports in `Sources/AlarmDomain/`** (`Repositories.swift`):
  `AlarmRepository` (CRUD upsert), `AuditRepository`, `SettingsRepository`,
  `OutboxRepository` — all `async throws`, `Sendable`. Plus the value types they
  need: `AppSettings` (feature flags, privacy-first defaults — all opt-in, cloud
  AI off per ADR-004) and `OutboxEntry` (+ `OutboxStatus`, `OutboxEntryID`).
- **No Apple framework type leaks into the ports** (acceptance criterion, and the
  headline #1/§5 rule): signatures reference only domain types + stdlib `String`;
  `Repositories.swift`/`AppSettings.swift` import nothing, `OutboxEntry.swift`
  imports only Foundation (for `UUID`/`Date`). The domain-purity lint covers all
  three files (verified).
- **Append-only is structural** — `AuditRepository` exposes no update/delete
  (#48). `OutboxStatus` and other enums are `String`-raw → unknown fails to decode
  (#27). `AppSettings`/`OutboxEntry` correctly live in `AlarmDomain` (the outbox
  speaks `AlarmCommand`; settings feed the policy layer).
- **`ios-architect` review shaped the outbox port for its WG-016 consumer**
  (additive now, not churn later): `OutboxStatus` gained `applied` (was
  `completed`) + **`uncertain`** (ARCHITECTURE §6 "reconcile after uncertain
  outcomes"; terminal = applied/failed); `OutboxRepository` gained
  **`unresolvedEntries()`** (reconciliation must recover stranded
  `inProgress`/`uncertain`, #10, not just `pending`) and **`entry(idempotencyKey:)`**
  (dedup lookup). `enqueue` documented idempotent-on-key; `markFailed` reason must
  be coarse/user-safe (#41); `save` must honor optimistic revision concurrency
  (WG-014); the retry cap is WG-016.
- **Consciously deferred:** audit pagination / bounded reads await the retention
  ADR (**ADR-009**, still pending) — additive later, not a breaking change; the
  outbox transition *mechanics* (retry, dedup enforcement, reconciliation) are
  **WG-016**. Implementations of all four ports are WG-013–016.

### WG-013 (2026-08-02): Configure persistence (Core Data)

- **`PersistenceController`** (`Sources/AlarmInfrastructure/`) stands up the Core
  Data stack per **ADR-002**: a **programmatic, versioned** `NSManagedObjectModel`
  (`versionIdentifiers`, `schemaVersion = "1"`), `NSPersistentContainer`,
  configurable in-memory (`/dev/null` SQLite — tests) vs on-disk
  (`FileProtectionType.complete`). **History tracking is on for both stores** so
  in-memory tests share production's reconciliation substrate (#10). Core Data is
  entirely confined to `AlarmInfrastructure` — no leak into the domain.
- **`@unchecked Sendable` is narrow and justified** — placed on the container
  owner (not the repository, per ADR-002's gate): `NSPersistentContainer` is
  Apple-documented safe to share across threads for context vending, and the
  thread-confined contexts are always used via `perform`. Repositories keep their
  own state actor-isolated.
- **Single settings-blob proof** that in-memory and Core Data repos **share one
  contract**: `CoreDataSettingsRepository` + `InMemorySettingsRepository` both
  conform to WG-012's `SettingsRepository` and pass one generic contract test.
- **`ios-architect` review (SDK-verified) caught a real Blocker** — concurrent
  `save()` created duplicate rows (the actor doesn't serialize across
  `await perform`) and reads went stale. Fixed with a `singletonKey` uniqueness
  constraint + `mergeByPropertyObjectTrump` (last-writer-wins) merge policy;
  a concurrent-save test now asserts exactly one row. Also removed a no-op
  `viewContext.automaticallyMergesChangesFromParent` and enabled in-memory history
  tracking.
- **Handoffs recorded for the repos built on this stack:**
  - **WG-014** wants the *opposite* merge policy — reject-on-conflict for
    `Alarm.revision` optimistic concurrency (the default `NSErrorMergePolicy`
    throws `133020`); settings' last-writer-wins is deliberately different.
  - **A `viewContext` reader observing background writes** needs the
    `NSPersistentStoreRemoteChangeNotification` wiring (deferred until a reader
    exists — UI/WG-018+); background contexts are siblings of `viewContext`, not
    children.
  - **WG-017** should spike the *heavyweight* migration stage (ADR-002 gate 1)
    early: a programmatic source+destination model + mapping model is more finicky
    than the `.xcdatamodeld` tooling Core Data expects; lightweight (added-entity)
    migration is verified to work.

### WG-014 (2026-08-02): Alarm repository (Core Data)

- **`CoreDataAlarmRepository`** (`Sources/AlarmInfrastructure/`, actor) implements
  WG-012's `AlarmRepository` over an `AlarmRecord` entity (id `String` unique,
  `revision` Int64, JSON `payload`; schema bumped to **v2**). It uses the
  **`NSMergePolicy.error`** (reject-on-conflict) policy — the deliberate opposite
  of the settings repo's last-writer-wins, per the WG-013 handoff.
- **Optimistic concurrency is belt-and-suspenders** (SDK-verified by the review):
  an **app-level guard** (`incoming.revision > stored` else typed
  `AlarmRepositoryError.staleRevision`) gives a clean error on the sequential
  path, and the **store-level** error merge policy + `id` uniqueness constraint
  reject the fetch-fetch-save-save race the guard can't see (mapped to
  `.conflict` via `NSManagedObjectMergeError`/`NSManagedObjectConstraintMergeError`).
  A 8-way concurrent test asserts **exactly one winner** and that **every loser
  throws a typed error** (no raw-`NSError` leak, no silent overwrite — #10).
- **Errors are typed:** `AlarmRepositoryError` (`.staleRevision(stored:incoming:)`,
  `.conflict(AlarmID)`, `.storageUnavailable`); the protocol stays untyped
  `throws`, so "typed" is delivered by the concrete type (codebase convention).
- **Handoff to WG-027:** `deleteAlarm` is **not revision-guarded** (the port takes
  no expected revision), so a stale delete could remove a newer alarm — routing
  deletes through the command processor's revision discipline is WG-027. Its save
  is still wrapped so a store conflict surfaces as a typed `.conflict`.
- Core Data stays confined to `AlarmInfrastructure` (no domain leak). The audit
  and outbox repositories are WG-015/016.

### WG-015 (2026-08-02): Append-only audit repository (Core Data)

- **`CoreDataAuditRepository`** (`Sources/AlarmInfrastructure/`, actor) implements
  WG-012's `AuditRepository` over an `AuditRecord` entity (id `String` unique,
  denormalized `alarmID` `String` for history-by-alarm, `timestamp` `Date`, JSON
  `payload`; schema bumped to **v3**, an additive lightweight migration).
- **Append-only is insert-only + idempotent on the event id.** `append` fetches by
  id first and no-ops if present — it never fetch-then-*updates*, so a recorded
  event is immutable via the port (#48). The port itself exposes no update/delete
  (WG-012). Under a concurrent same-id race the store-level `id` uniqueness
  constraint + `NSMergePolicy.error` reject the loser, which `append` absorbs as an
  idempotent no-op (`isConflict` → `context.rollback()`); a test asserts 8 racing
  same-id appends yield exactly one row with no thrown error, and 8 distinct ids
  all persist. **Caller precondition:** an `AuditEventID` identifies one event's
  content (ids come from the injected generator); a reused id with different content
  would be silently dropped, not detected.
- **Ordering** for both queries is `(timestamp ASC, id ASC)` — chronological with a
  deterministic tiebreak so equal-instant events return in a stable order across
  queries (verified: Core Data string sort matches Swift `String <` for UUIDs, and
  `Date` round-trips through `deferredToDate` identically to the sort column).
- **Reads are resilient, not strict (review MAJOR, 2 reviewers):** a single
  undecodable `payload` row (future schema, bit-rot, or a fail-closed unknown enum
  in `AuditActor`/`CommandSource`) is **skipped**, not rethrown, so one poison row
  cannot blind the whole user history / diagnostic query (#49). The corrupt row
  **stays in the store** — append-only is preserved; it is only dropped from the
  view. *Encoding on `append` stays strict* (a corrupt write fails loudly).
  Surfacing a count of skipped rows is deferred (needs diagnostics infra; never log
  the raw payload, #41). **Follow-up:** `CoreDataAlarmRepository` (WG-014) has the
  same throwing-`compactMap` pattern; fixing it is out of WG-015 scope (no
  cross-task refactor) and is flagged for a follow-up task.
- **"Sensitive fields excluded" — what actually holds (review, all 3):** #41's
  *enumerated* categories (health samples, precise location, calendar titles,
  journal text, LLM prompts) are excluded **by construction** — no such field
  exists anywhere in the `AuditEvent`/`AlarmCommand`/`Alarm` graph, and state deltas
  are stored as hashes (`old/newStateHash`). **But** `.create`/`.update` embed the
  full `Alarm`, so its free-text **`label` is stored verbatim** in the append-only
  trail. This is **accepted for MVP** (on-device, `FileProtectionType.complete`,
  never transmitted). The three in-code comments that had claimed "only hashed state
  / no fields" were corrected to say this, and the prior sensitive-exclusion test
  (a strawman using `.snooze`, which embeds no `Alarm`) was replaced with one that
  appends a `.create` whose `label` is `"take insulin 20u"` and asserts the
  enumerated markers are absent while honestly asserting the label *is* present.
- **Handoff to WG-027 (privacy):** a **label-redaction boundary** for the audit
  (and outbox, which embeds the same command — `OutboxEntry.command`) belongs at the
  command processor, since a redacted label in the audit must not lose the real
  label the outbox needs to schedule AlarmKit. Same task should constrain
  `userVisibleReason` to a coarse, vetted vocabulary (mirror the outbox's
  `markFailed(reason:)` contract). Erasing a sensitive label already captured in the
  append-only trail also interacts with #42/#43 (deletion/export) — track there.
- **Append-only is a port guarantee, not a store/tamper-evident one:** the app is a
  single module, so any code can open the container directly. Store-level
  tamper-evidence (hash-chained events) is a future ADR, not this task.
- **Handoff to WG-017:** the `schemaVersion`→`versionIdentifiers` bump is
  documentation/telemetry only — Core Data triggers inference from structural
  version *hashes*, not the identifier string; don't rely on it as the migration
  trigger. Cross-instance audit persistence (second controller on the same on-disk
  store) is deferrable to the migration harness (in-memory `/dev/null` can't show
  it).

### WG-016 (2026-08-02): External-operation outbox (Core Data)

- **`CoreDataOutboxRepository`** (`Sources/AlarmInfrastructure/`, actor) implements
  WG-012's `OutboxRepository` over an `OutboxRecord` entity (id `String` unique,
  **`idempotencyKey` `String` unique**, denormalized `status` + `createdAt` for
  queries, JSON `payload`; schema → **v4**). Merge policy is `NSMergePolicy.error`
  (consistent with alarm/audit).
- **Idempotent enqueue (at-most-once):** fetch-by-key-first + the `idempotencyKey`
  uniqueness constraint that absorbs the concurrent race (`isConflict` →
  `rollback()`). Enqueue also **normalizes** the row to `.pending`/`attempts = 0` so
  a caller cannot seed the queue mid-lifecycle (defense in depth). ios-architect
  verified (real Core Data) that 12-way concurrent same-key enqueue yields exactly
  one row and never throws.
- **Guarded state machine** (`resolve`/`beginAttempt`/`setStatus`, pure + Core Data
  plumbing split for lint complexity): `pending → inProgress → applied/uncertain/
  failed`. A terminal entry is never resurrected into a second external apply;
  `mark*` are idempotent on their own state. A concurrent read-modify-write on the
  same entry is rejected with a typed **`.conflict`** (store optimistic lock) — no
  silent lost update, no `attempts` inflation — verified by ios-architect probes and
  a `testConcurrentMarkInProgress…` regression test (attempts == winners).
- **Bounded retries (no unbounded retries):** `markInProgress` counts attempts and,
  past `maxAttempts` (5), fails the entry and throws `retryLimitExceeded`. Keeping
  the alarm active on exhaustion is the caller's safe fallback (#40).
- **Recovery:** `unresolvedEntries()` = every non-terminal entry (pending/inProgress/
  uncertain); reads are resilient (skip a corrupt row, per WG-015).
- **Review (alarm-safety + ios-architect, both SDK-verified): no blocker.** Applied:
  reworded doc comments that overstated the guarantees, enqueue normalization, and
  the missing `mark*` concurrency test. Two MAJORs the alarm-safety agent raised are
  **recovery-semantics delegations to WG-029, not outbox bugs** — recorded below.
- **Handoffs to WG-027 (command processor):** it is the **single command-
  serialization boundary** (ARCHITECTURE §6) — the outbox does not stop two
  independent processors from each driving one entry, so WG-027 must not run the
  live worker and launch reconciler over the same entry concurrently. It constructs
  `.pending` entries, derives an `idempotencyKey` **unique per logical operation** (a
  reused key is deduped forever), and on `retryLimitExceeded`/`.failed` keeps the
  alarm safe (#40). A `mark*` `.conflict` is **retryable** — re-read and re-apply,
  never treat as terminal.
- **Handoffs to WG-029 (reconciliation):** (a) a terminal **`.failed`** op (incl.
  retry-exhausted, or a crash after the fail-commit but before WG-027 secured the
  alarm) is intentionally absent from `unresolvedEntries()`; recovering it is
  WG-029's **independent local-alarm-vs-AlarmKit divergence scan**, not an outbox
  scan — add a WG-029 test that a `.failed` entry with an unscheduled alarm is
  repaired. (b) An **`uncertain`** entry must be reconciled by **reading AlarmKit
  ground truth before any re-drive** — never a blind `markInProgress`, which at the
  cap would wrongly declare it `.failed`, violating #10. (c) An **undecodable** row
  is skipped by every query (a liveness gap — neither retried nor terminalized);
  WG-029 should quarantine/terminalize it so #40 engages.
- **Known permissive transitions (documented, caller-driven):** `pending → applied/
  uncertain` is allowed without a prior `inProgress`, and re-`markInProgress` from
  `inProgress` inflates `attempts` (each attempt to reach AlarmKit is real). WG-027
  drives transitions in order; these are not guarded further to keep the mechanism
  simple.
- **Privacy:** an `OutboxEntry.command` embeds the same `Alarm` (incl. free-text
  `label`) for `.create`/`.update` as the audit — the label-redaction boundary is
  the same WG-027 handoff recorded under WG-015 (#41/#42/#43).

### WG-018 (2026-08-03): Dependency container and environment composition

- **`AppEnvironment`** (`Sources/AppComposition/`, a `Sendable` struct) is the
  composition root: it holds the six ports (`WallClock`, `IdentifierGenerator`, and
  the four repositories) and exposes two **explicit** graphs — `production()`
  (on-disk Core Data + `SystemClock`/`SystemIdentifierGenerator`) and
  `inMemory(clock:identifierGenerator:)` (ephemeral `/dev/null` Core Data +
  injectable clock/ids for tests and previews). Both list every dependency in one
  `make(...)`, so the wiring is reviewable.
- **Not a service locator:** there is no global/`shared` instance — the graph is
  passed by injection only. This is enforced by a new `domain_no_composition_root`
  SwiftLint rule (mirrors `domain_no_apple_frameworks`) that errors if `AppEnvironment`
  is referenced anywhere outside the composition layer (AppComposition/WakeGuardApp);
  its `included` list covers **every** other module (domain, application,
  cross-cutting, and infrastructure). Verified the rule fires with a throwaway domain
  probe.
- **Ports promoted to the domain:** `WallClock` and `IdentifierGenerator` moved from
  `TestSupport` into `Sources/AlarmDomain/` (mirroring `Repositories.swift`, so the
  domain owns its ports); the live adapters (`SystemClock`,
  `SystemIdentifierGenerator`) live in `AppComposition`, and the deterministic fakes
  (`TestClock`, `DeterministicIDGenerator`) stay in `TestSupport`, now conforming via
  `@testable import WakeGuard`.
- **SwiftUI injection is an *optional* environment key** (`\.appEnvironment`,
  default `nil`). A non-optional **fataling** default was tried and **rejected**:
  SwiftUI evaluates a custom key's default during scene setup at app launch, so a
  `fatalError` there crashes the app / test host even when the graph is correctly
  injected. The contract is therefore: a consumer that reads `nil` MUST present an
  explicit safe state (e.g. a storage-unavailable screen), **never** a silent
  empty-success render that would falsely show "no alarms" (review MAJOR-2). Previews
  inject the non-throwing `AppEnvironment.preview` (in-memory) so they are never nil.
- **Launch:** `WakeGuardApp.init` builds `production()` synchronously on the main
  actor (loadPersistentStores is synchronous for a local store). For the small store
  this is sub-millisecond; the only watchdog risk is a future heavyweight migration
  on a large store — an accepted MVP tradeoff, revisit with WG-017. On failure the
  app shows `CompositionErrorView` (honest: storage unavailable, alarms not loaded,
  no false safety claim; copy avoids recommending a destructive reinstall for the
  transient file-protection-before-first-unlock case).
- **Review (ios-architect, SDK-verified): no blocker.** Applied: MAJOR-1 — the test
  no longer calls `production()` (which writes the real fixed-path on-disk store); it
  asserts the live adapters directly + the container's default adapters via the
  in-memory graph. MAJOR-2 — the optional-key contract above. MINOR — widened the
  lint rule + fire-verification, a `Sendable` compile-time guard test, the watchdog
  comment, and the softened error copy.
- **Handoff to ADR-003 (package extraction):** when `AlarmDomain` is extracted, its
  ports (`WallClock`/`IdentifierGenerator`/the repo ports) become `public` and
  `TestSupport` switches from `@testable import WakeGuard` to `import AlarmDomain`.
  The extraction stays mechanical; this is the only added step.
- **Handoff to E03/WG-027 (consumers):** screens/services read ports from
  `@Environment(\.appEnvironment)` (constructor injection for non-View consumers).
  The container currently exposes no `PersistenceController` directly (repos are the
  interface); add it only if reconciliation (WG-029) needs it.

### WG-024 (2026-08-03): AlarmKit adapter port and fake

- **`AlarmManagerAdapter`** (`Sources/AlarmDomain/`, Foundation-only) is the
  domain-owned port to the system alarm authority — the concrete adapter is the
  **only** component that calls AlarmKit (#1), invoked only by the command processor
  (#2). Methods: `authorizationState` (non-throwing read) + `requestAuthorization`;
  `schedule`; `cancel`; `snooze(alarmID:until:)`; `scheduledAlarms` (query). Neutral
  types: `AlarmAuthorizationState`, `AlarmScheduleRequest`, `ScheduledAlarmSnapshot`,
  `AlarmManagerError`. The real AlarmKit-backed adapter (imports AlarmKit) is WG-026;
  tests/previews use the fake.
- **`.uncertain` is the load-bearing safety primitive (#10):** mutating calls return
  `Void`, so a caller cannot obtain a success token from an unknown outcome — the
  only way to learn the truth is `scheduledAlarms()`. This *forces* reconciliation
  and maps to the outbox's `.uncertain`. A **cancelled** task must also be treated as
  `.uncertain` (documented; ARCHITECTURE §6).
- **`FakeAlarmManagerAdapter`** (`Tests/TestSupport/`): tracks the system set
  (schedule adds / cancel removes / snooze reschedules preserving criticality / no
  fabrication on snooze-of-absent), records append-only **call logs** (distinct from
  the idempotent system set), and lets tests set auth state, **seed** the system set
  (divergence, WG-029), and **inject** a per-operation failure or `.uncertain`
  (thrown without applying; the "applied-but-unconfirmed" orphan case is modeled by
  `setScheduled` after the throw).
- **Review (alarm-safety + ios-architect, both SDK-verified): no blocker.** Applied
  in-scope: added `.restricted` auth state (WG-025 needs it), added **`isCritical` to
  `ScheduledAlarmSnapshot`** so reconciliation can catch a critical→non-critical
  drift (a silent suppression risk, not only presence/time), documented the
  cancel-is-not-stop boundary and cancellation→uncertain, made snooze non-fabricating,
  de-overclaimed the request doc, and added orphan-schedule / call-log / restricted
  tests.
- **Handoff to WG-025 (authorization flow):** builds the pre-prompt explanation,
  denied/**restricted** recovery, and Settings deep link *around* the
  `requestAuthorization` primitive; a thrown request = state unknown → preserve the
  last safe alarm (never treat as an implicit denial that weakens a critical alarm).
- **Handoff to WG-026 (real adapter):** must uphold `schedule` idempotency via a
  **persisted `AlarmID` ↔ AlarmKit-id mapping** (losing it risks a duplicate alarm),
  map `Alarm.sound`/recurrence without dropping intent, and map caught AlarmKit
  errors to a **fixed coarse** `.failed(reason:)` (never `String(describing:)`, #41 —
  add a redaction test). Whether `ScheduledAlarmSnapshot` needs an external id / a
  challenge-`stop` primitive / a scheduled-vs-ringing flag depends on the AlarmKit
  API surface WG-026 sees.
- **Handoff to WG-029 (reconciliation):** discharges the WG-011 occurrence-identity
  note (DECISIONS §WG-011: `(AlarmID, fireTime)` with no revision) — WG-029 must
  reconcile a **stale occurrence** (queued before a reschedule) by revision, and must
  never cancel a **currently-firing** alarm when repairing "extra" system alarms.
- **Handoff to WG-073 (challenge → stop):** stopping a *ringing* alarm (only after a
  valid challenge pass, #24) is a **separate primitive** to add to this port then —
  `cancel` is for scheduled/future alarms only and must never target a firing one.
- **Docs:** the `AlarmManagerAdapter` name is now realized in code; reconciling
  ARCHITECTURE §4's service list to name it is a deferred doc cleanup (kept out of
  this feature's scope).

### WG-025 (2026-08-03): AlarmKit authorization flow

- **`AlarmAuthorizationCoordinator`** (`Sources/AlarmApplication/`, Foundation-only)
  orchestrates authorization around the WG-024 adapter primitives: `currentStep()`
  reads state without prompting; `requestAfterExplanation()` issues the one-time
  system request; `openSettingsIfAppropriate()` deep-links to Settings. It maps
  `AlarmAuthorizationState` → a closed `AlarmAuthorizationStep` (`explainThenRequest`
  / `authorized` / `deniedOpenSettings` / `restrictedUseFallback` / `unknownKeepSafe`).
  `SettingsOpener` is a port so the flow stays framework-free; the real UIKit opener
  is supplied by the app shell.
- **Read-only w.r.t. alarms (#10):** the coordinator invokes no mutating adapter
  method (only `authorizationState`/`requestAuthorization`), so a denial/restriction/
  interruption can never drop a scheduled alarm — the caller keeps its existing
  alarms. It *holds* an adapter that can mutate, so this is enforced by
  `testFlowNeverMutatesAlarms`, not capability confinement (single-target build).
- **Recovery:** denied → Settings deep link (gated to denied only — a Settings link
  can't lift a restriction); restricted → non-AlarmKit fallback; a thrown/interrupted
  request → `.unknownKeepSafe`, **never** an assumed denial that would weaken a
  critical alarm (#10). A still-`notDetermined` result after a request is likewise
  kept-safe (no re-prompt loop; iOS prompts once, then routes to Settings).
- **Review (alarm-safety + ios-architect, both SDK-verified): no blocker.** Applied:
  corrected the "no mutating capability" doc (it's test-enforced), strengthened the
  request contract, added the still-notDetermined test.
- **MAJOR resolution — explanation-before-request ownership:** the flow routes
  `.notDetermined → .explainThenRequest`, but it **cannot observe whether a screen was
  actually shown** — so *displaying* the explanation and gating the request is the
  **permission-UI task's** contract (a bare `requestAfterExplanation()` is possible in
  the type system; a witness token was rejected as it breaks the step's `Equatable`
  ergonomics and still can't prove display). No safety harm — a premature prompt drops
  no alarm.
- **Handoffs to the permission-center UI task (WG-036):** owns the explanation
  screen + enforcing explanation-before-request, the **"critical alarm + denial"
  urgency messaging** (the flow has no notion of what's scheduled), and consuming
  `AlarmAuthorizationStep` (which fuses state+action — a screen wanting "denied" +
  both "Open Settings" and "Use fallback" may want a separate view-state).
- **Handoffs to WG-026 / app shell:** the concrete **UIKit-backed `SettingsOpener`**
  (`UIApplication.openSettingsURLString`) imports UIKit, so it lives in the app shell
  (decide: SwiftUI app target vs a UI-infra layer — not AppComposition if kept
  UIKit-free). The coordinator + real adapter + real opener become `AppEnvironment`
  members (one line each in `make(...)`) when the real adapter lands.
- **Manual verification:** the real on-device authorization prompt is exercised only
  with the real adapter (WG-026) + permission UI — deferred, not testable here.

### WG-026 (2026-08-03): AlarmKit schedule mapping — per-occurrence, not native recurrence

- **The load-bearing decision: per-occurrence `.fixed`, native `.relative` recurrence
  REJECTED.** `AlarmKitScheduleMapper` (`AlarmInfrastructure`) maps every schedule to
  `.fixed(instant)` at the next occurrence from the pure `AlarmSchedulingEngine`
  (`schedule(for: ScheduleRule, after: now, in: timeZone)`). An initial attempt mapped
  `.weekly` → AlarmKit **native `.relative(.weekly)`** recurrence; adversarial review
  (alarm-safety + ios-architect) rated it **2 BLOCKERs** and it was reverted after
  human sign-off: native recurrence (a) forks the committed per-occurrence model
  (WG-024's per-`fireTime` port, WG-029's scalar-`fireTime` reconciliation), and (b)
  cedes tz/DST resolution to AlarmKit (violating #13) and **cannot express a
  fixed-zone weekly alarm** — AlarmKit `.relative` fires wall-clock in the *device's*
  zone, so a `stayFixed` critical alarm would silently mis-fire while traveling (#16).
  Per-occurrence keeps the pure engine authoritative (#13): the caller passes the zone
  it resolves from `TravelBehavior` via `schedulingTimeZone` (WG-021), so fixed-zone
  vs follow-device is the domain's explicit choice, and AlarmKit gets a resolved
  instant. **Consequence:** the app must re-drive recurrence (schedule-ahead + launch/
  foreground reconciliation) so a recurring alarm stays dependable without a BGTask
  (#10) — that is a WG-027/WG-029 responsibility (see handoffs).
- **External-id correlation is identity.** `AlarmKit.Alarm.ID` is a `UUID` the caller
  supplies (`AlarmManager.schedule(id:configuration:)`), so `AlarmID.rawValue` *is* the
  system id — no persisted mapping (resolves the WG-024 concern; verified from the iOS
  26.5 SDK swiftinterface).
- **Minimal live adapter** `SystemAlarmManagerAdapter` (the only caller of
  `AlarmManager`, #1; compiles against the real SDK, not unit-testable): schedules a
  `.fixed` alarm with a plain title + Stop-button presentation; **guards
  `authorizationState == .authorized`** before scheduling so a denial is a typed
  `.notAuthorized` that mutates nothing (#10); maps AlarmKit errors to **coarse**
  `.failed(reason:)` (never `String(describing:)`, #41 — unit-tested via the internal
  `map(_:)`) and `CancellationError` → `.uncertain` (#10).
- **Criticality (review BLOCKER, resolved by documentation + a mandatory device
  check):** the iOS 26 AlarmKit API exposes **no app-facing criticality knob**
  (`AlarmConfiguration`/`AlarmAttributes`/`Alert` have none — verified from the SDK).
  AlarmKit alarms are *system* alarms that ring through silent mode/Focus by default
  (the #6–#8 baseline), so scheduling a critical alarm as a standard AlarmKit alarm is
  **not** under-alerting — but this ring-through **must be verified on a device**
  (WG-030), and until then no critical alarm is actually scheduled (the adapter is not
  yet wired). The `.critical` *tier*'s distinct guarantee (explicit cancel-confirmation)
  is enforced at the policy/command layer (WG-028/WG-027), not the adapter. AlarmKit
  does not return criticality on read-back, so `ScheduledAlarmSnapshot.isCritical` can
  not be populated by the real adapter — **WG-029 must compare against locally-tracked
  intent**, not the read-back field.
- **Documented minimal-adapter limitations (handoffs):**
  - **Snooze loses the label:** `snooze(alarmID:until:)` reschedules with a generic
    "Alarm" title (the port carries no title, and AlarmKit doesn't expose it on
    read-back). **WG-027 should snooze by re-issuing `schedule(request)` with the
    retained domain label**, not the adapter's bare `snooze`.
  - **`scheduledAlarms` skips non-`.fixed`** system alarms (all WakeGuard alarms are
    `.fixed`); a foreign/`.relative` alarm under our ids would be invisible — **WG-029
    should treat a known local alarm with no matching `.fixed` system alarm as
    divergence.**
  - No `.unavailable` mapping yet (AlarmKit service errors class as `.failed`); refine
    once the AlarmKit error taxonomy is confirmed on device.
- **Handoff to WG-027:** compute occurrences via the engine (zone from
  `schedulingTimeZone` only, #16); schedule several occurrences ahead + re-arm on
  ring/launch so recurring alarms are dependable without a BGTask (#10); use
  `schedule` (retained title) for labeled snooze.
- **Handoff to WG-030 (real-device smoke):** verify a **critical alarm rings through
  silent mode / Focus / DND**; schedule/cancel/authorization round-trips; AlarmKit's
  `cancel(id:)` behavior for an unknown id (the adapter defensively no-ops via a
  presence check); and add `NSAlarmKitUsageDescription` + the AlarmKit capability to
  the project when the adapter is wired and first calls `AlarmManager` (today AlarmKit
  is only implicitly autolinked and no runtime call is made).

### WG-027 (2026-08-03): Transactional alarm command processor

- **`AlarmCommandProcessor`** (`AlarmApplication`, `actor`) is the **single command
  boundary** and the only invoker of `AlarmManagerAdapter` (#2). Per command:
  **authorize** (#3 — a `.rejected` mutates nothing) → **persist local alarm** (source
  of truth first, #10) → **audit** the mutation (#46) → sync to AlarmKit with the
  **outbox bracketing** the external call (enqueue → markInProgress → schedule/cancel →
  markApplied / **markUncertain** / markFailed). `AlarmPolicyEngine` is a new
  domain-owned authorization **port** (the real engine is WG-028); a fake authorizes in
  tests.
- **#10 crash-safety:** local-first means the alarm survives every failure — a
  `.failed`/`.uncertain` external preserves the saved alarm, and an `.uncertain` leaves
  the outbox entry for reconciliation (never assumed not-done). A cancelled adapter call
  maps to `.uncertain` too. **Crash recovery of a stranded outbox entry / a
  local-vs-system divergence is WG-029's job — WG-027 is only crash-safe once WG-029
  lands.**
- **Per-command scope:** create/update/enable/disable applied fully. Occurrence-level
  commands (snooze / cancelOccurrence / rescheduleOccurrence) return **`.unsupported`**,
  not a success-like `.noOp`, so a future caller can never mistake a dropped snooze for
  success (review MAJOR). markChallengePassed / reconcile / recover return `.noOp`
  (fail-safe; owned by WG-073 / WG-029).
- **Review (alarm-safety + ios-architect, both SDK-verified): no blocker.** Applied:
  the `.unsupported` split; re-read the stored outbox entry after the key-dedup'd
  enqueue and mark *its* id (not a phantom fresh id), honoring the retry cap;
  `CancellationError → .uncertain`; a distinct concurrent-edit reason vs a storage
  failure on save; honest audit reasons (describe the *local* mutation, not the
  external) and dropped a false "recovered at launch" claim.
- **Deliberate design points:** the audit records the **local** mutation; the external
  sync outcome lives in the **outbox** — a full user history joins the two (WG-048). The
  state fingerprint is a Foundation-only **FNV-1a** hash (change-detection, not crypto
  or tamper-evidence). Alarm-save and outbox-enqueue are **not co-committed** (separate
  repo actors); reconciliation covers the gap — a two-phase commit with AlarmKit is
  ruled out by ADR-002. Audit writes are best-effort (`try?`); an audit gap is **not
  yet** repaired at launch (a state-vs-audit backfill is a follow-up).
- **Revision discipline:** enable/disable — the processor loads, bumps `revision`, and
  saves. update — the **caller** provides the bumped revision (optimistic concurrency);
  the processor surfaces the repo's stale-revision rejection as a concurrent-edit reason.
- **Handoffs:** WG-028 implements the real `AlarmPolicyEngine`. WG-029 re-drives
  uncertain/pending outbox entries by reading AlarmKit ground truth (never by
  re-`process`-ing the same command — the key dedups it), re-arms recurring alarms
  (schedule-ahead), and backfills audit/state gaps. WG-048 joins audit + outbox for the
  external outcome in history. A dedicated **serialization** task must guarantee
  no-interleave under concurrent commands (the actor releases isolation at each `await`;
  the alarm repo's revision guard prevents a lost *local* update, but external ordering
  under a race is not strictly serialized). Full application of the occurrence-level
  commands is a WG-027 follow-on. There is no `AlarmCommand.delete` — deletes go through
  `.disable`; a hard delete, if added, routes here (WG-014 handoff, still open).

### WG-028 (2026-08-05): Deterministic alarm policy engine

- **`DefaultAlarmPolicyEngine`** (`AlarmApplication`, Foundation-only) implements the
  WG-027 `AlarmPolicyEngine` port: it is the deterministic authorization authority —
  **the policy engine, not the model, decides** (#3, #31). It evaluates all four factors
  the acceptance criteria name: **criticality, actor (source), user confirmation, and
  time-to-fire**, and every denial carries a **user-displayable, coarse** reason (never
  raw sensitive text, #41).
- **Rules.** Additive/system commands (`create` / `enable` / `markChallengePassed` /
  `reconcile` / `recover`) are always authorized — they add or preserve protection.
  **Destructive** commands (`disable` / `cancelOccurrence` / `rescheduleOccurrence` /
  `snooze` / `update`) are gated: (a) a critical alarm from `.agentProposal` is
  **rejected outright — even flagged confirmed** (#4: an AI can never suppress a critical
  alarm; verified by test); (b) a critical alarm without confirmation is rejected (#6);
  (c) a non-critical but **imminent** alarm (next fire within the window) without
  confirmation is rejected. An `.update` of a **non-critical** alarm is authorized (only
  weakening a *critical* alarm is gated — a downgrade-to-standard or a fire-far-away edit
  is still gated because the *current* alarm loaded is critical). A genuinely absent
  alarm (`nil`) → authorized (a no-op cancel).
- **Fail closed on an unknown read (review BLOCKER, fixed).** `alarm(id:)` has three
  outcomes: an alarm, `nil`, or a **thrown** `storageUnavailable`. A thrown error is
  **not** "no alarm" — the engine cannot weigh criticality it could not read, so it
  **rejects** (fails closed), never fails open. The initial `try?` collapsed the throw
  into `nil` → `.authorized`, which a transient storage fault could have used to
  authorize an unconfirmed critical suppression from the user *or* the AI. Now only a
  definite `nil` authorizes.
- **`isImminent` respects `isEnabled` (review MAJOR, fixed).** The scheduling engine
  deliberately ignores `isEnabled` (the caller decides), so the policy engine gates a
  **disabled** alarm out of imminence — else a disabled alarm inside the window would be
  gated *and* falsely told "about to go off" (a false safety status). A critical disabled
  alarm is still gated by the criticality branch, independent of imminence.
- **Imminent window = 300 s**, a `static let` (the time-to-fire factor). Chosen as a
  conservative "about to ring" threshold; kept a compile-time constant (not injected) for
  MVP — promote to a defaulted `init` parameter if a per-alarm/per-user window is ever
  needed. This safety constant's operational definition belongs to **ADR-007** (critical
  alarm defaults, still unscheduled). The check is **inclusive** (`<=`) and one-sided —
  it gates on the alarm's **next** occurrence, ignoring the specific `fireTime` an
  occurrence-level command targets (MVP-conservative: it gates *more*, never less) and
  not treating an actively-/just-firing alarm as imminent (a symmetric lower bound needs
  a `previousOccurrence` primitive that does not exist yet). Both are intentional; WG-085/
  WG-086 should know the next-occurrence semantics before adding occurrence UI.
- **Confirmation is a trust boundary, by design.** The engine decides **when**
  confirmation is required; the caller/UI proves **that** the user confirmed by passing
  `userConfirmed`. The engine cannot verify a human acted, so the standing contract for
  the not-yet-wired callers is: **only a synchronous, user-initiated confirmation UI may
  pass `userConfirmed: true`; the agent path must never set it** (and a critical alarm is
  rejected regardless of the flag). `AlarmCommandProcessor.process` defaults
  `userConfirmed: false` — a caller that forgets it gets the safe (unconfirmed) path.
- **Port change.** `authorize` gained `userConfirmed: Bool` (the WG-027 port had no
  confirmation input, but #6 requires it). Threaded through the processor and the fake;
  two conformers, one caller, all updated. Extending the existing port (vs a second port)
  keeps one atomic authorization decision — a caller can't consult one gate and skip the
  other.
- **Deferred: pure engine (review MAJOR, design — deferred with rationale).** The engine
  is **repo-backed** (it loads the target alarm), so it and the processor each read the
  same alarm — a duplicate read, and (because the processor `actor` releases isolation at
  each `await`) a narrow window where the policy could authorize against revision *N*
  while the processor mutates *N+1*. The architect's alternative — a **pure** function
  taking `(targetAlarm, now, deviceTimeZone)` with the processor loading once — would
  remove all three. Deferred because: the one *sharp* edge (fail-open-on-read-error) is
  fixed directly above; the residual (duplicate read, stale snapshot) is low-probability,
  caught by the repo's optimistic-revision guard, and already owned by the **WG-027
  serialization follow-up**; and re-refactoring the just-changed port + reworking the
  safety-critical processor now would broaden WG-028's scope against the one-task rule.
  Recorded here so the pure-engine option is not lost.
- **Reviews (alarm-safety-reviewer + ios-architect, both read the real files).**
  alarm-safety: **1 BLOCKER** (fail-open on read error — fixed) + **1 MAJOR** (`isImminent`
  ignored `isEnabled` — fixed), both proven with throwaway probe tests; confirmed #6
  completeness across all destructive commands, the AI downgrade-then-suppress path is
  closed, source integrity, #3 routing, and deny-reason safety. ios-architect: **no
  blocker**; layering/`Sendable`/lint clean, port ripple complete; the pure-engine MAJOR
  deferred above; test-coverage MAJORs applied (see below).
- **Tests added for the review findings:** storage-read-error fails closed for both a
  user and an agent; a disabled alarm inside the window is authorized; an AI snooze of a
  critical alarm is rejected (#6 "delayed"); cancelling an occurrence of a critical alarm
  needs confirmation; the 300 s boundary is inclusive (300 s gated, 301 s authorized).
- **Handoffs.** WG-044 (critical-alarm config UI) and WG-042/WG-085 (create/edit,
  turn-off-today) are the first real callers — they must pass `userConfirmed` explicitly
  from a user-initiated confirmation and never from the agent path. WG-171 (agent
  permission settings) layers feature-gating on top. The engine is **not yet wired into
  `AppEnvironment`** (only the alarm repo is composed today); #3 is a unit-level guarantee
  until the UI/processor wiring lands. Feature-flag/kill-switch and permission inputs
  (ARCHITECTURE §8) are not yet consulted — add when those callers exist.

### WG-029 (2026-08-05): Launch/foreground reconciliation (ground-truth)

- **Two pieces.** `AlarmReconciler` (`AlarmDomain`, **pure**, ARCHITECTURE §127):
  `plan(desired:system:now:deviceTimeZone:) -> [ReconciliationRepair]` compares the
  desired system state (each **enabled** alarm's next occurrence via
  `AlarmSchedulingEngine`) with a `ScheduledAlarmSnapshot` of the system authority and
  emits `.schedule` for a **missing** or **divergent** (fire time or `isCritical` drift)
  alarm and `.cancel` for an **extra** one. `AlarmCommandProcessor.reconcile()`
  (`AlarmApplication`) reads ground truth + desired, runs the planner, and applies each
  repair as a `.systemReconciliation` / `.reconciliation` action, auditing every repair.
- **Ground-truth, not outbox-replay.** WG-029 reconciles against **what AlarmKit actually
  holds vs. desired**, which is authoritative regardless of outbox state and recovers the
  *effect* of any stranded operation. It is **idempotent by construction**: once the
  system matches desired, the plan is empty (no oscillation, no duplicate schedule).
- **#2 preserved — reconcile lives in the processor.** Only `AlarmCommandProcessor`
  invokes the adapter (#2), so the reconcile **driver** is a processor method (a same-file
  `extension`, which keeps `alarmManager` `private`); the §127 "AlarmReconciler" is
  realized as the **pure planner** (no adapter). A separate component that read
  `scheduledAlarms()` itself would be a second adapter-invoker — rejected.
- **Fail-safe (#10).** If ground truth **or** the desired read *throws*, reconcile repairs
  nothing and returns `skipped` — it never repairs against an unknown system, and (the
  catastrophic case) never treats a *failed* desired read as "no alarms" and cancels every
  system alarm. The `try?`→`nil` (failed) vs `[]` (genuinely empty → cancel extras)
  distinction is load-bearing and tested. A repair that **hard-fails** is audited +
  counted; a repair whose outcome is **uncertain** (interrupted / cancelled — the adapter
  may or may not have applied) is counted **apart** (`ReconciliationSummary.uncertain`),
  not as a failure, and re-checked next pass — mirroring the command path's uncertain
  handling (review MAJOR, fixed).
- **No re-authorization.** Reconcile converges to **already-authorized local intent**
  (system-matches-local); it is not a new user/agent mutation, so it does not re-enter
  `AlarmPolicyEngine` (reconcile/enable/create are non-destructive there anyway). Cancel
  is **future-only**, so reconcile can never stop a ringing alarm (#24). Audit records
  **nil** old/new state hashes because a repair mutates **system**, not local, state (the
  local alarm is unchanged) — an intentional #47 reading, not a miss.
- **Reviews (alarm-safety + ios-architect): no blocker.** Applied: honest
  uncertain/cancelled repair accounting (was mislabelled hard-`failed`); + a fixed-zone
  planner test (#16 anchor-zone), a multi-repair sort-order test, and an
  uncertain-during-reconcile test.
- **Deliberately deferred (documented, reviewer-endorsed — all liveness/scope, not
  safety):**
  - **Outbox terminalization / undecodable-row quarantine** (the WG-016/WG-027 handoff):
    ground-truth reconcile already restores the divergence, so non-terminal outbox entries
    are harmless (idempotency-keyed) but accumulate — terminalizing/quarantining them is a
    follow-on. **This supersedes the WG-027 handoff wording** ("WG-029 re-drives uncertain/
    pending outbox entries"): WG-029 delivers *ground-truth* reconciliation; outbox
    cleanup is separate.
  - **The scene-phase trigger + `AppEnvironment` composition.** `reconcile()` is shipped +
    tested but **nothing calls it yet** (the processor is not composed — consistent with
    WG-028). The eventual launch + `.active` trigger must drive both the command worker and
    reconcile through a **single** processor instance (§6 serialization).
  - **`isCritical` read-back seam.** The planner's criticality-divergence check needs the
    adapter read-back to report real `isCritical`; the WG-026 adapter cannot yet, so against
    it every critical alarm looks divergent each pass → a redundant (same-time, harmless)
    reschedule. Resolve when the real read-back supplies criticality (or track intended
    criticality locally). On the release checklist.
  - **`SkipReason` observability** (which read failed) — deferred until a privacy-safe
    logging consumer exists (WG-019 / diagnostics).
- **Structure note.** To stay under `type_body_length`/`file_length`, `reconcile()` is a
  same-file extension, `CommandOutcome` moved to its own file, and `ReconciliationSummary`
  to `AlarmDomain` beside `ReconciliationRepair`. `AlarmCommandProcessor` is now near both
  limits — flagged for the **serialization / decomposition follow-up** the architect
  recommended.
