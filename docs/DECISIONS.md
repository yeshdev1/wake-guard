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

### WG-030 (2026-08-05): Schedule/cancel/snooze integration tests (scope)

- **Test-only.** WG-030 adds `AlarmSchedulingIntegrationTests` over the processor →
  adapter → persistence path; **no production code changed** — every path already existed
  (WG-026/027/029). It fills the gaps WG-027's tests left: the injected-failure matrix on
  **cancel**, the remaining **schedule** errors (notAuthorized / unavailable), real
  **cancellation races** on both operations, and the occurrence-command safe contract —
  each asserting the safe persisted outcome (#10).
- **Snooze is not implemented end-to-end.** Processor-level `.snooze` (and
  cancelOccurrence / rescheduleOccurrence) remain **`.unsupported`** — the WG-027
  occurrence-level deferral is **not** re-opened here (full snooze couples to the ring /
  challenge flow, WG-073). "Snooze integration" is covered at the **adapter** level
  (WG-024's fake tests) plus the processor's unsupported safe contract (authorized,
  audited `noOp`, **no** adapter / outbox / local side effect).
- **Cancellation races** are modelled with a real `Task.cancel()` and an adapter that
  `Task.checkCancellation()`s at the external boundary — deterministic because `cancel()`
  runs before the task can traverse the ~6 async persistence hops to reach the adapter.
  The processor maps the resulting `CancellationError` to `.uncertain` and leaves the
  outbox for reconciliation (#10), never assuming the op did not happen.
- **Confirmed WG-027's local/external audit split:** a failed external schedule audits the
  **local save** as `.succeeded` (the alarm is durably persisted) while the failure lives
  in the **outbox**; the enabled-but-unscheduled alarm is re-armed by ground-truth
  reconciliation (WG-029), not an outbox retry.

### WG-040 (2026-08-05): Design tokens and reusable components

- **Tokens** (`Sources/DesignSystem`): semantic **Dynamic-Type** typography (scales with the
  user's text size), a fixed **spacing / radius** scale (referenced instead of raw literals,
  so there are no hard-coded layout assumptions), and **system-semantic colors**
  (`.systemBackground` / `.primary` / status `.green` / `.red` / `.orange` / `.secondary`)
  that adapt to **dark mode and Increase Contrast** automatically. No asset catalog — the
  system colors carry adaptation for free.
- **Status is never color-alone:** `AlarmStatusStyle` = (label, SF Symbol, tint); the label
  and icon carry meaning, the tint only reinforces. **Presentation-only** — it maps from a
  domain status at the view layer, so `DesignSystem` keeps no alarm-domain dependency (lint
  also keeps it out of the composition root; it may import SwiftUI as a non-domain module).
- **Components:** `StatusBadge`, `SurfaceCard`, `PrimaryButtonStyle`, `DestructiveButtonStyle`.
- **No snapshot testing** (no third-party SDK): visual / dark-mode / Dynamic-Type checks are
  `#Preview`s; unit tests pin the deterministic token + status-model invariants (spacing
  ascending; every status carries text + icon; critical ≠ scheduled beyond color).
- **Review (ux-accessibility-reviewer): 1 BLOCKER + 3 MAJOR, all fixed.**
  - **BLOCKER:** `StatusBadge` drew the text **and icon** in the saturated tint — ~2–3:1,
    **failed WCAG AA for every status**, and made the icon shape low-contrast (undercutting
    the "do not rely on color alone" defense). Fixed: label + icon in `.primary` (auto
    ≥4.5:1, adapts to dark / contrast); the tint is a 15%-opacity **background wash** only.
  - **MAJOR:** primary vs destructive differed **by color alone** (both solid-filled). Fixed:
    the destructive style carries a leading danger glyph (`xmark.octagon.fill`, distinct from
    the critical-status triangle) — a grayscale / color-blind-robust signal.
  - **MAJOR:** white-on-accent/red fills are only ~3.6–4.0:1. Fixed: the filled-control label
    is **bold**, clearing the large-text (3:1) bar at every Dynamic Type size; re-verify on
    device if the shipped accent is ever lightened (`RELEASE_CHECKLIST`).
  - **MAJOR:** a `ButtonStyle` cannot own an `.accessibilityIdentifier` / hint. Documented the
    **caller convention** — screens (WG-041+) set an identifier and, on destructive buttons,
    an `.accessibilityHint`.
- **Deferred — localization debt (documented, reviewer-endorsed):** `AlarmStatusStyle.label`
  is a plain `String` (also the VoiceOver label), so the status vocabulary is English-only.
  The app has **no string catalog yet** and `RootView` is likewise unlocalized — localization
  is an **E11** concern. When the catalog lands, make these `LocalizedStringResource`; not
  re-introduced piecemeal here, to avoid inconsistency with the rest of the app.

### WG-041 (2026-08-05): Alarm list + next-alarm summary — the E03 screen template

- **Pattern (every E03 screen copies this):** an `@MainActor @Observable` view model owned
  by the view via `@State(wrappedValue:)`, handed its **ports** (`AlarmRepository`,
  `WallClock`) + a device-zone closure by the view (which reads them from
  `@Environment(\.appEnvironment)`). The VM is **read-only** — it never mutates an alarm or
  calls the adapter (#2) — and computes the next occurrence via the **same**
  `AlarmSchedulingEngine.nextOccurrence` the processor and reconciler use, so the displayed
  time can't disagree with what fires. Screens live in `WakeGuardApp` for now.
- **Safety-display contract:** a failed load is `.failed`, **never** `.empty` (#10 / WG-018)
  — a storage failure is never rendered as "no alarms"; `.failed` and the nil-environment
  safe state both say so explicitly (the nil-env branch is defensive — the shell normally
  intercepts a composition failure with `CompositionErrorView`). Regression-tested.
- **States:** loading / empty / loaded(summary + list) / failed. **Reconciliation is a
  non-blocking banner** (an `isReconciling` flag), not a blanking state — the last-known
  alarms stay visible while it verifies. The trigger is the WG-029 follow-on;
  `setReconciling(_:)` is the seam (tested).
- **Review (ux-accessibility + ios-architect): no blocker; 5 MAJOR applied.**
  - **Stale next-ring:** a one-shot `.task` + a single `clock.now` snapshot could show a
    past fire time after an alarm rings. Fixed: reload on appear **and on every foreground**
    (`scenePhase → .active`), with a **latest-load-wins** generation guard so overlapping
    reloads can't clobber a fresher result.
  - **Next-ring text:** was an absolute datetime ("Nov 15, 2023 at 7:00 AM"); now a
    **relative day + time** ("Today / Tomorrow / weekday, 7:00 AM", 12/24h-aware), matching
    the previews.
  - **VoiceOver:** dropped the duplicated "Off, Off" for disabled alarms; a **critical**
    alarm now **leads** its announcement ("Critical alarm. …").
  - **Dynamic Type:** rows + summary **reflow to vertical** (`ViewThatFits`) at large text
    so the next-ring time never truncates; added an accessibility-XL preview.
- **Deferred (documented):** the reconcile **trigger** (WG-029 wires `setReconciling`);
  **time-zone-change** reload (foreground reload covers the common case; observe
  `NSSystemTimeZoneDidChange` when travel UI lands); a dedicated **feature-UI folder** if
  E03 crowds `WakeGuardApp` (ADR-003 permits it — revisit as screens multiply);
  **localization** (strings are literals, consistent with the WG-040 debt — String Catalog
  in E11); extra **critical visual prominence** beyond the badge + a11y lead (revisit with
  the critical-config screen, WG-044).

### WG-042 (2026-08-06): Create-alarm flow + command-processor composition

- **The flow.** `CreateAlarmView` + `CreateAlarmViewModel` build a validated `Alarm` from the
  form (name, schedule kind [weekly / one-time], time, weekday chips / date), preview the next
  occurrence live, and submit `.create` — creation goes **only** through the command processor,
  never persistence or the adapter directly.
- **Mutation boundary.** A new `AlarmCommandProcessing` protocol (conformed by
  `AlarmCommandProcessor`) is what the UI depends on, so a screen can't reach the adapter or
  persistence and can be tested with a fake. `AppEnvironment` now composes the processor (+
  `DefaultAlarmPolicyEngine`) over the repos and exposes it — so a create is authorized (#3),
  audited (#46), and routed through the single adapter boundary (#2).
- **Validation = "can it ring?"** `canSave = (nextOccurrence != nil)`, and `save()`
  **re-checks it at submit time** — a one-time can lapse into the past between the preview and
  the Save tap. So a past one-time, an empty weekday set, or an invalid date is unsaveable
  (all yield no occurrence). DST ambiguous / nonexistent wall-clock times resolve forward via
  the engine (non-crashing); explicit DST *policy* is WG-022.
- **Deferred AlarmKit (the key decision).** The processor is composed with an interim
  **`DeferredAlarmManagerAdapter` that makes NO AlarmKit calls** — the real
  `SystemAlarmManagerAdapter` needs the authorization-prompt UI, `NSAlarmKitUsageDescription`,
  and on-device verification, a cohesive later step (WG-025 UI / WG-030). Consequence: a
  created alarm is **saved locally (#10) but does not ring yet**. This is disclosed by a
  **persistent banner** (gated on `AppEnvironment.schedulesAlarmsInSystem == false`), so a
  saved alarm is never silently implied to ring. Swapping in the real adapter + flipping the
  flag is a one-line change.
- **Criticality** defaults to `.standard`; the user-facing critical toggle is WG-044 (#31 —
  the policy engine assigns criticality; nothing here lets the model do so, and no AI path
  touches create).
- **Reviews (alarm-safety + ios-architect + ux-accessibility): no blocker.** Applied: the
  `save()` future-ness re-check (top safety finding — a lapsed one-time was previously
  submittable as a dead alarm reported "created"); the disclosure banner; accessibility
  (weekday chips reflow via `LazyVGrid` + `.isToggle` + a non-color selected cue + 44pt
  targets; the live preview is `updatesFrequently`; a Save-disabled hint; a labelled name
  field); adapter `snooze → .unavailable`; and 4 new tests (minute-boundary re-validation,
  exact submitted schedule fields, today-earlier-time, empty-label).
- **Deferred with ADR — the real-adapter outcome seam.** When `SystemAlarmManagerAdapter` is
  composed, a *genuine* schedule failure returns `.failed` **with the alarm already persisted**
  (local-first), which the create flow would surface as "couldn't create" for an alarm that
  *was* created. The AlarmKit-integration task (WG-025 UI / WG-030) must fix the
  outcome→message mapping (distinguish a local-persist failure from a post-persist sync
  failure, or verify via the repo) before the real adapter ships.

### WG-043 (2026-08-07): Edit / enable / disable / delete flows

- **The flows.** Row actions (tap-to-edit, an enable/disable `Toggle`, swipe-to-delete) and the
  edit form all route through `AlarmCommandProcessing` (#2/#3/#46) — no screen touches
  persistence or the adapter. Enable/disable emit `.enable`/`.disable`; delete emits a new
  `.delete`; edit reuses the create form to emit `.update`.
- **`.delete` command + ordering (the key safety decision).** Added `.delete(AlarmID)` (domain +
  policy `isDestructive` + processor `applyDelete`). Delete is **local-first, then a best-effort
  system cancel**: once the local record (source of truth, #10) is gone the delete is *done*, so a
  failed/uncertain system cancel does **not** downgrade the result — `applyDelete` returns
  `.applied`. Rationale: a stranded system alarm is the *safe* direction for a wake app (a spurious
  ring, never a missed alarm) and is reaped by WG-029 reconciliation's extra→cancel scan. The
  reverse order (cancel-then-delete) is **rejected**: a cancel that succeeds before a failed local
  delete would silently stop a still-listed alarm from ringing — the dangerous direction. The
  earlier `applyDelete` comment claimed a stranded alarm "can never ring after a delete"; that
  overstated an unwired reconcile trigger and was corrected to describe the real mechanism.
- **First-class `.needsConfirmation` outcome.** `PolicyDecision` and `CommandOutcome` gained
  `.needsConfirmation(reason:)`, returned only from the critical/imminent-unconfirmed branches
  (#6). This disambiguates a **confirmable** gate (re-submitting with `userConfirmed: true` *will*
  authorize) from a **non-confirmable** `.rejected` (a fail-closed read error, or an AI proposal
  barred by #4). Previously both were `.rejected`, so a transient read error during a destructive
  action surfaced as a nonsensical "Confirm change" dialog whose Confirm re-submitted into the same
  rejection. The processor now authorizes via an **exhaustive switch**, so a `.rejected` or
  `.needsConfirmation` can never fall through and mutate state.
- **Confirmation UX.** Submit unconfirmed → `.needsConfirmation` → the view prompts with the
  reason → re-submit confirmed. The list **reloads on the pending path** so an optimistic toggle
  snaps back to true state under the alert; the confirm alert's presentation binding **restores
  true state on any non-button dismissal** (symmetric with the error alert); delete uses
  **`allowsFullSwipe: false`** so a critical alarm is never destroyed by a reflexive full-swipe and
  its confirmation is always reached by a deliberate tap. The enable/disable toggle names the alarm
  and the on/off consequence for VoiceOver (the switch trait already speaks the value — not
  color-alone).
- **Edit = generalized create.** `CreateAlarmView`/`CreateAlarmViewModel` now edit: same id,
  `revision + 1` (optimistic concurrency), preserved `criticality`/travel/sound/policies (only
  label + schedule are editable here — criticality is WG-044), future-ness re-validated at save.
- **File-length relief.** Extracted `AlarmCommandProcessor+Reasons.swift` (the pure state-hash +
  failure-reason formatters — no adapter/persistence surface, so no #2 impact) and
  `AlarmListComponents.swift` (the shared banner/message views) to keep both files under the
  400-line limit.
- **Reviews (alarm-safety + ios-architect + ux-accessibility): no blocker shipped.** Applied the
  delete-outcome coherence + honest comment (safety B1/M1), the `.needsConfirmation` split (arch
  M1), no-full-swipe (UX B1), pending-path reload (UX M2), confirm-binding restore (UX m4), and
  toggle a11y (UX M1); +2 tests (non-confirmable rejection ≠ prompt; failed-system-cancel delete).
- **Deferred (with rationale).**
  - **Full `AlarmCommandProcessor` decomposition.** The formatter extraction relieved this task,
    but the outbox-bracketing helpers should move to a collaborator before the *next* command case
    lands (recurring `file_length` / `type_body_length` pressure, first flagged WG-029).
  - **Telegraph critical status in the edit form** (a read-only badge) → **WG-044**, which owns
    critical-config UI; the save-time confirmation already gates a critical edit.
  - **Row-action in-flight serialization.** A rapid double-toggle is convergent and safe (the
    processor's `.noOp`/revision guard + latest-load-wins); the pending-path reload fixes the
    visible symptom. A full in-flight guard is a minor follow-up.
  - **Delete outbox key** reuses the `"cancel"` kind; it fails safe (reconciliation reaps a
    skipped cancel), a distinct `"delete"` key is a minor follow-up.
  - **Imminent non-critical *edit* not gated.** A documented WG-028 choice (only *critical* edits
    gate; imminent still gates disable/delete). Unchanged — not a #6 violation.
  - **Past one-time edit** shows a generic "can't ring yet" on save; noted on the manual checklist.

### WG-044 (2026-08-07): Critical alarm configuration

- **The toggle.** A "Critical alarm" toggle in the create/edit form (`CreateAlarmViewModel.isCritical`,
  seeded from the edited alarm, threaded into both build paths). Editing now takes criticality from
  the toggle (closing the WG-043 UX-M3 gap — an alarm's critical status is telegraphed and editable).
  A plain-language footer explains what critical means (#9).
- **#31 — a model may not assign criticality (the key decision).** A new policy guard
  (`DefaultAlarmPolicyEngine.modelCriticalityChange`) rejects any `.agentProposal` command that
  creates a critical alarm or changes an alarm's criticality. It is placed **before** the additive
  fast-path: a `.create` is additive (`isDestructive` is false), so the guard must precede the
  `isDestructive` early-return or an agent `.create(critical)` would be authorized. The rejection is
  **not confirmable** (a model can't confirm, cf. #4). It **fails safe**: an unreadable or absent
  `.update` target reads as `.standard`, so any incoming non-standard criticality differs and is
  rejected (the fallback only ever makes the guard fire more readily). A regression test pins the
  guard-before-fast-path ordering.
- **Changed a WG-028 assertion — a tightening, not a weakening.** `testAdditiveCommandsAreAuthorized`
  `EvenForCriticalFromAgent` asserted an agent may create a critical alarm (`.authorized`). WG-044
  flips that to `.rejected` (#31), a strengthening. The genuinely-additive assertions (an agent may
  add a *standard* alarm, and enable an existing one) are preserved. Per CLAUDE.md this is recorded
  here because it changes an established policy expectation — it does not weaken a safety invariant.
- **Confirmation asymmetry.** Weakening a critical alarm (critical → standard) requires confirmation:
  the WG-028/043 `.update` gate reads the alarm's **stored** criticality, still critical at authorize
  time, so the toggle can't launder a critical alarm past #6. Strengthening (standard → critical) and
  a user creating a critical alarm are additive → authorized without a prompt. A **user** may assign
  criticality; a **model** may not.
- **Reviews (alarm-safety + ux-accessibility): no blocker.** alarm-safety verified #31 is complete
  (every criticality-carrying command covered — only `.create`/`.update` carry an `Alarm`; the guard
  precedes the fast-path; the read fails safe) and the change is a net strengthening. Applied:
  softened the "rings even when silent/Focus/DND" copy to "**is designed to** ring …" — an accuracy
  fix, since the interim `DeferredAlarmManagerAdapter` doesn't ring yet and AlarmKit's ring-through
  behavior must be device-verified (WG-026/031); plus the guard-ordering regression test.
- **Deferred (with rationale).**
  - **Gate the "designed to ring" copy on `schedulesAlarmsInSystem`** so the create sheet mirrors the
    list's "won't ring yet" banner — the list already discloses it globally; a small follow-up.
  - **A stronger VoiceOver binding of the footer to the toggle** — the section-footer pattern is
    iOS-idiomatic, and the consequence is also spoken at the Save confirmation (the decisive moment),
    so the safety impact is bounded. The `.accessibilityHint` supplements the visible footer.
  - **Localization** of the toggle label / footer / reasons (E11).
  - **No agent→`process` path is wired yet** — the #31 guard is defense-in-depth ahead of the AI
    epoch (E08/E09); today it is exercised only by tests, which is the intended hardening.

### WG-045 (2026-08-07): Wake-challenge configuration UI

- **The config surface.** A "Wake challenge" section in the create/edit form: None / Walk; when
  Walk, bounded steppers for duration and minimum steps, an accessible-alternative picker (tap
  sequence / press and hold), and a footer that discloses the phone-carry requirement (#25).
  `ChallengeDraft` (a value type on the `@Observable` view model, so the form binds to
  `challenge.*`) holds the facets and builds a validated `ChallengePolicy`; it is seeded from the
  edited alarm so editing shows and re-saves the current challenge.
- **Only the safe facets are exposed.** Duration, minimum steps, and the accessible alternative are
  user-facing. The anti-cheat internals (cadence cap, pause budget, anti-cheat threshold) live in a
  new domain `WalkChallenge.standard` factory with validated defaults and are **not** surfaced — the
  UI can never weaken the anti-cheat. Keeping them in the domain (not the view layer) is deliberate.
- **Accessible alternative always available (SCOPE §2.3 / #22).** A `.walk` challenge carries an
  `accessibleFallback` by domain construction; `ChallengeDraft.accessibleFallback` is non-optional
  and defaulted, so a required challenge can never lack an alternative for a user who can't walk or
  carry the phone.
- **Thresholds within validated bounds + the cadence coupling (the key safety fix).** Steppers bind
  to `durationRange` (5–60 s) and a duration-derived steps range, and `build()` clamps defensively.
  Crucially, duration and minimum steps are **coupled**: the required cadence (steps ÷ duration) is
  held in a plausible-walk band — at most `plausibleWalkCadence` (2.0 steps/s), kept safely **below**
  the anti-cheat `maximumCadence` (4.0), so a legitimate walk can always pass (no unsatisfiable
  challenge / lockout — a **false-fail**); and at least `minWalkCadence` (0.5), so a long window
  can't be trivialized by incidental motion (a **false-pass**). motion-red-team found the decoupled
  corners (5 s + 50 steps = 10/s, unsatisfiable and above the anti-cheat cap; 60 s + 5 steps =
  0.08/s, trivial); the coupling closes both, proven by a grid-sweep test over the whole reachable
  configuration space.
- **Reviews (ux-accessibility + motion-red-team): no blocker.** Applied: the cadence coupling (the
  material motion fix), and stable VoiceOver label + value on the steppers (matching the weekday-chip
  precedent) so an increment announces just the changed value.
- **Deferred (with rationale).**
  - **A domain-level satisfiability invariant** (`minimumSteps / targetDuration ≤ maximumCadence` in
    `WalkChallenge.init`) would defend every construction path, but risks rippling into WG-010's
    tests and the exact relationship (with real motion units) is WG-072/075's to define. The
    config-layer band is stricter than mere satisfiability and closes the user-facing gap now; the
    domain invariant is a recommended follow-up.
  - **The footer disclosure is a `Section` footer** — iOS-idiomatic; VoiceOver reaches it as the
    section's last element (same trade-off recorded for WG-044's critical footer).
  - **`antiCheatThreshold = 0.5` is an inert placeholder** until WG-072/075 define its units.
  - **The phone-carry disclosure text is not unit-tested** (it's View text; the repo has no
    ViewInspector/UI-test target) — covered by the manual checklist.
  - **Localization** of the section labels / footer (E11).

### WG-046 (2026-08-07): Travel-policy configuration UI

- **The config surface.** A "When you travel" section in the create/edit form: the three MVP
  options (Follow local time / Keep home-zone time / Ask when I travel), an accessible display of
  the anchor IANA zone, and a per-option preview of destination behavior. `TravelOption` maps
  to/from the domain `TravelBehavior`; `.regionRule` (WG-021, not user-creatable in the MVP) maps
  to Ask, preserving its rule-based, never-silently-shift spirit.
- **No option shifts a schedule silently (#16); no location/GPS.** Follow-local and keep-zone are
  explicit fixed policies; ask prompts before shifting. Nothing here reads location — the anchor is
  the device's **IANA identifier** (a coarse on-device signal), never GPS/position. privacy-security
  confirmed: no Core Location, IANA not offsets (#11), data-minimized, no logging.
- **Anchor preservation on edit (the safety fix — the review's one MAJOR).** Before WG-046 the edit
  path rebuilt the schedule from the *current device zone*, silently re-anchoring an edited alarm —
  a pre-existing WG-044 behavior, invisible until WG-046 surfaced the anchor. Now `buildSchedule`
  **preserves the edited alarm's stored anchor zone** (never re-anchoring to the device zone) and
  `anchorZoneID` displays that stored anchor, so editing a "keep home-zone" New York alarm while
  travelling in Tokyo keeps it anchored to New York (#16). The picker time is still decomposed in
  the device zone (the zone the seed composed it in), so the displayed number round-trips; the
  stored `IANATimeZone` is reused directly, avoiding the `TimeZone("UTC").identifier == "GMT"`
  normalization that would reject a UTC anchor. A regression test edits a NY alarm in Tokyo and
  asserts the saved anchor stays NY.
- **Copy honesty.** `.ask` is stated as the alarm's *policy* ("will ask before shifting if your
  time zone changes") — the travel *detection* is E06, not built yet — and `.followLocal` says "in
  whatever time zone your device is in" (not "wherever you are") so nothing implies location
  tracking. A guardrail test forbids "GPS"/"location"/"track" in any option's copy and pins the #16
  "never moves the alarm on its own" assurance.
- **Reviews (ux-accessibility + privacy-security): no blocker.** Applied: anchor preservation (ux
  M1), copy softening (privacy MINOR-1/2), and the two regression/guardrail tests.
- **Deferred (with rationale).**
  - **A friendlier localized zone name** (e.g. "Eastern Time") — the acceptance is "IANA zone
    displayed accessibly," and the readable IANA identifier ("America/New York" visually, "America,
    New York" for VoiceOver) meets it; a localized name would *hide* the IANA zone.
  - **The destination preview is a `Section` footer** — iOS-idiomatic; VoiceOver reaches it as the
    section's last element (parity with WG-044/045).
  - **Editing a fixed-zone alarm's *time* while in another zone** shows the raw wall-clock number
    interpreted in the anchor zone — an inherent wall-clock-across-zones nuance (WG-022 territory),
    not re-opened here; the anchor itself is preserved (above).
  - **Localization** of the option titles / labels / preview (E11).

### WG-047 (2026-08-07): Pre-alarm-policy configuration UI

- **The config surface.** A "Smart pre-alarm" section in the create/edit form: enable + a bounded
  lead-time window (5–120 min, default 30) + which actions the prompt offers (Turn off today /
  Change time / Remind later — PRODUCT_SPEC §3.3; "Keep original alarm" is the implicit no-op).
  `PreAlarmDraft` builds a validated `PreAlarmPolicy`; it is seeded from the edited alarm.
- **Domain extension (minimal, spec-driven).** `PreAlarmPolicy` gained
  `allowedActions: Set<PreAlarmAction>` (the spec's prompt actions). The factory param defaults to
  `[]` (existing callers unaffected); Codable decodes it with `decodeIfPresent ?? []` so pre-WG-047
  data still loads; an unknown action string fails **closed** (throws, #27). `.disabled` keeps an
  empty set and strips stray actions on decode. The `leadTime > 0` bound is unchanged.
- **#7 + critical limit, config-only (the safety framing).** The `allowedActions` set records
  **intent only** — the pre-alarm prompt runtime is E05, and any actual "turn off / change" it later
  triggers still routes through the command processor + policy engine, which gates a critical
  alarm's destructive change behind #6 (proven by the existing `testUpdateGatesOnlyCriticalAlarms`).
  So configuring `.turnOffToday` can never cancel a critical alarm without confirmation.
  `promptDisclosure` always states #7 ("if you don't respond, the alarm rings unchanged at its set
  time"); it adds an informational-only note when no actions are offered, and appends the critical
  confirmation limit when the alarm is critical (visible + live via `model.isCritical`).
- **Reviews (alarm-safety + ux-accessibility): no blocker.** alarm-safety verified the #6/#7
  guarantees are enforced by tested code (not just comments), the decode fails closed, and no config
  path bypasses the engine. Applied: the informational-only note for enabled-with-no-actions (ux M1
  — it was the default state, whose copy otherwise implied actions existed); a 5-minute-grid
  alignment on a seeded off-grid lead time so it can't silently desync the stepper (safety MINOR-2);
  action-toggle VoiceOver hints (ux m1); and de-duplicated the section header vs the enable-toggle
  label (ux m4 — header "Smart pre-alarm", toggle "Check before the alarm").
- **Deferred (with rationale).**
  - **The critical limit sits in the section footer** (not a dedicated in-body `Label`) — accepted
    debt, parity with WG-044's "extra critical prominence" posture; it is text (not color-alone) and
    updates live.
  - **A per-toggle "needs confirmation" annotation** for critical alarms — the footer disclosure
    suffices for a config task; the runtime enforces #6.
  - **The pre-alarm evaluation windows / awake-inference runtime** (ADR-008 / E05 —
    `PreAlarmEvaluator`); this task is config only.
  - **Localization** (E11), and an AX5 screenshot reference for the section (manual checklist).

### WG-048 (2026-08-07): Alarm history / audit detail UI

- **The screen.** A read-only per-alarm history: a `List` of the alarm's append-only audit trail
  (newest first), each row showing who / what / when / outcome, tappable to a detail (What / Who /
  When / From / Result). Entered from the edit form's "History" link (editing only).
  `AlarmHistoryViewModel` maps each `AuditEvent` to a safe `AlarmHistoryItem`; the states mirror
  WG-041 (loading / empty / failed / loaded), and a failed load reads distinctly from empty — a
  storage error never shows as "no history."
- **Sensitive internals never surface (#41).** The mapping carries only `userVisibleReason` (the
  command processor's coarse, user-safe text) plus friendly actor / source / outcome / timestamp.
  The state hashes and the correlation id are **structurally absent** from `AlarmHistoryItem`, so
  they can't reach the UI; the raw `command` / `Alarm` / `label` are never rendered.
  privacy-security verified end-to-end (including that `userVisibleReason`'s only producer emits
  fixed coarse strings), and a regression test injects a hash + a correlation UUID and asserts
  neither appears in any surfaced string.
- **Recovery/reconciliation distinct (#50).** A **system-originated** action (reconciliation /
  recovery / migration, by actor or source) gets a distinct icon + a "System" text tag + a "System
  action." VoiceOver prefix (never color-alone), and the detail replaces the redundant "From" with
  a "system action, not a change you made" note. This deliberately **broadens the domain's narrower
  `AuditEvent.isRecovery`** (which is only `.recovery`) so that reconciliation entries are
  distinguished from ordinary edits too — the acceptance pairs "recovery/reconciliation", and the
  first cut only flagged `.recovery`.
- **Read-only (#48).** The view reads only `auditRepository.events(forAlarm:)` and offers no
  mutation of the append-only trail.
- **Reviews (privacy-security + ux-accessibility): no blocker.** privacy-security returned **PASS
  with no findings**. Applied ux: the system-distinction + detail restructure (M1); the outcome/tag
  line **reflows at large Dynamic Type** (`ViewThatFits`) so the outcome — the non-color signal —
  can't truncate (M2); `noOp` → "No change needed" (so a re-sync reason doesn't read as
  contradictory); and a plainer "Automatic recovery" actor label.
- **Deferred (with rationale).**
  - **A top-level "all history" view and deep links** — this history is per-alarm, entered from the
    edit form; deep-linking to alarm/proposal screens is WG-049.
  - **The interpolated accessibility label is English word-order** ("who: what outcome, when") — the
    hardest string to localize later; folded into the E11 localization work.
  - **Localization** (E11); an AX5 screenshot reference (manual checklist).

### WG-049 (2026-08-07): Deep links for alarm and proposal screens

- **The link layer.** `DeepLinkParser` decodes a `URL` into a **navigational** `DeepLinkRoute`
  (`.alarm(AlarmID)` / `.proposal(UUID)` / `.unknown`). A route carries only ids — **structurally
  no `AlarmCommand`** — so following a link can only open a screen, never mutate an alarm (#7). The
  parser is pure and **total**: any malformed / unknown-host / wrong-scheme / over-long link →
  `.unknown`, with no force-unwrap. `DeepLinkModel` resolves a route by **reading** the alarm repo:
  found → present the edit screen; stale/unknown id → "no longer exists"; a *thrown* read → "try
  again" (distinguished, fail-safe); proposal → "not available" (no E09 screen invented);
  nil-environment → "not ready." A monotonic request token makes a later link supersede an
  in-flight one.
- **Safety verified.** alarm-safety fuzzed ~30 hostile URLs (path-traversal, homoglyph host, extra
  segments, opaque/empty-host, userinfo/port/query) — all resolve to the exact alarm or `.unknown`,
  never a crash or coercion — and confirmed **empirically** that opening a link never invokes the
  command processor (the stored revision is unchanged); a critical alarm's edit still routes through
  the #6-gated processor on Save. **No blocker/major.**
- **Forward guard for the AI/notification epochs (do not lose this).** The pre-alarm (E05) and
  AlarmKit actions will deliver via this same URL layer; the design forces them through the
  navigational parser, so a future "Turn off today" action can only open a confirmation screen — it
  can never be wired to auto-cancel. **E05 must keep notification actions navigational-URL-only** (or,
  if a `.notificationAction` command source is ever used, still route through `AlarmPolicyEngine`
  with #6). This is the whole point of a route carrying no command.
- **Deferred — on-device delivery + presentation integration (coupled; lands with the URL
  emitters, E05 / WG-025-030).** Honest scope: the routing *logic* ships and is tested; on-device
  *delivery* does not work yet.
  - **Scheme registration.** `CFBundleURLTypes` can't be a scalar `INFOPLIST_KEY_`, so registering
    `wakeguard://` requires switching the app target from `GENERATE_INFOPLIST_FILE: YES` to an
    XcodeGen `info:` block — an Info.plist-generation change that can't be device-verified this
    session. Nothing emits `wakeguard://` URLs yet, so an unregistered scheme is **fail-closed**
    (no link fires — the safe direction). **Recipe for the follow-up:** add
    `info: { path: Config/WakeGuard-Info.plist, properties: { UILaunchScreen: {},
    UIApplicationSceneManifest: { UIApplicationSupportsMultipleScenes: true },
    CFBundleURLTypes: [ { CFBundleURLName: com.wakeguard.app, CFBundleTypeRole: Editor,
    CFBundleURLSchemes: [wakeguard] } ] } }`, drop `GENERATE_INFOPLIST_FILE` + the two
    `INFOPLIST_KEY_*Generation` lines, regenerate, and confirm the built plist has both the scene
    manifest and the URL types.
  - **Presentation collision.** RootView currently presents the deep-linked alarm's edit sheet,
    which can collide with the alarm list's own create/edit sheets if a link arrives while one is
    open (SwiftUI drops the second → the link no-ops; never a mutation, #7 holds). The follow-up
    consolidates to a **single edit-sheet presenter** driven by both tap-to-edit and deep-link.
  - Consequence: criterion 1 ("notification/AlarmKit actions route safely") is met **at the logic
    level**; its **on-device verification is pending** the registration (`RELEASE_CHECKLIST.md`).
- **Applied from review:** the rapid-link race (request token + reset-both-fields, tested). MINOR
  parser leniency (`//` / trailing-slash still resolve to the exact target — safe) left as-is.
- **Deferred (other):** localization of the error copy (E11).

### WG-050 (2026-08-07): UI tests for core alarm flows

- **The suite.** `WakeGuardUITests` (a new `bundle.ui-testing` target) drives the app through its
  accessibility identifiers — six flows: launch/empty-list, create, edit-persists (round-trips a
  critical change through persistence), delete, critical-delete-confirmation (#6), and travel-option
  selection. Screenshots of key states (empty list, create form, critical alarm, the confirm alert,
  travel options) are attached (`XCTAttachment`, `keepAlways`) for the release baseline.
- **Isolation via a launch hook.** The app honors a `-uiTesting` launch argument → composes
  `AppEnvironment.inMemory()` instead of `production()`, so each launch starts from a clean, empty,
  in-memory store and a test run never reads or writes the user's real alarms. **Gated behind
  `#if DEBUG`** so this test-only affordance is compiled out of release builds (a test hook must
  never ship in a safety app; launch args can't be injected in a shipped app anyway).
- **Kept out of the fast gate.** The UI target lives in its own scheme (`WakeGuardUITests` /
  `make test-ui`), not the `WakeGuard` scheme's `test` set, so `ci-fast` stays a quick unit-only
  gate. The UI suite (~90 s — it launches the app per test) is run on demand / in a fuller CI.
- **XCUITest robustness patterns (recorded so future UI tests reuse them).** The alarm row combines
  its children into one accessibility element (`.ignore` + a custom label), so it is matched by
  identifier on **any** element type, not `buttons`. A SwiftUI `Toggle`'s plain `.tap()` does not
  reliably flip the switch, so the helper verifies the value and falls back to a coordinate tap on
  the control edge. The critical-create flow leaves the label blank so the keyboard never covers the
  toggle. (Root cause of the flaky-looking first run: both were XCUITest interaction quirks, not app
  bugs — the underlying flows are covered by unit tests too.)
- **No reviewer** — low-risk test infrastructure; the only production change is the DEBUG-gated
  launch hook.
- **Deferred:** on-device screenshot-baseline approval and running the UI suite in remote CI
  (`RELEASE_CHECKLIST.md`); localization-variant screenshots (E11).

### WG-060 (2026-08-07): Normalized motion source ports

- **Four independent ports.** `PedometerSource` / `MotionActivitySource` / `DeviceMotionSource` /
  `AltimeterSource` — each a distinct `Sendable` protocol (`availability() async` + a live
  `samples()` `AsyncThrowingStream`), so the walk challenge and awake-inference depend on exactly
  the sources they need and degrade gracefully. Distinct protocols (not a generic base) preserve the
  compile-time "exactly the sources I need" independence. Foundation-only; the CoreMotion mapping is
  `MotionInfrastructure` (WG-062+).
- **Every sample carries timestamp + quality** via a `MotionSample` protocol (normalized,
  framework-neutral value types).
- **Explicit availability, never a silent nil.** `MotionSourceAvailability` distinguishes
  `notPresent` / `notAuthorized` / `restricted` / `temporarilyUnavailable` (so WG-061 can tell
  "Settings fixes it" from "it won't"), and a source that can't deliver **throws**
  `MotionSourceError.unavailable` through its stream — a missing sensor reads as "no data →
  fallback", never "no movement → false fail" (#21).
- **Anti-cheat sufficiency (the review's key finding — frozen into the Codable contract now, since
  adding fields later is a breaking change).**
  - `PedometerSample.secondsSinceLastStep` — the inter-step-interval **series** across the stream
    yields cadence *regularity/variance*; a steady rhythmic tap is implausibly regular and a real
    gait varies, which a smoothed `cadenceStepsPerSecond` scalar cannot express (WG-069/070).
  - `DeviceMotionSample.gravityAngleFromVerticalRadians` — a privacy-safe **scalar** (not the raw
    axes) whose stability separates a phone carried by a walker from one shaken on a nightstand
    (WG-065), so a shake can't win on magnitude alone.
- **Stream contract (documented on the ports).** Each `samples()` begins a **new, non-replayable,
  non-buffering** live stream; a thrown error is **terminal**, and a consumer treats it — and any
  non-`MotionSourceError` throw — as fail-closed "keep the alarm, offer the fallback" (#24). Sample
  timestamps are **not** guaranteed monotonic/fresh (consumers reject stale/out-of-order,
  WG-063/067); `stepCount` is cumulative-within-episode (anti-replay is WG-070). `FakeMotionStream`
  can inject a mid-attempt drop, so the false-FAIL trace is testable.
- **Activity confidence.** For `MotionActivitySample` the inherited `quality` **is** the classifier
  confidence (`CMMotionActivity.confidence`), so a barely-cleared `.walking` is distinguishable from
  a high-confidence one (WG-064); `.unknown` is a live "unsure" value distinct from an undecodable
  one (ambiguous ⇒ non-passing).
- **Deferred with rationale.**
  - **Sample-value validation** (reject negative counts / non-finite magnitudes) lives at the
    `MotionInfrastructure` adapter boundary where untrusted CoreMotion data enters (WG-062), and
    re-validates on decode once a *persisted* motion-history store exists (WG-081). No
    persisted/untrusted-decode path exists today — a deliberate deviation from the
    value-type-validates precedent (`ScheduleComponents`): boundary data is validated at the
    boundary, keeping the carrier simple.
  - **Historical bounded-window query** (awake-inference) is a **separate additive port**
    (WG-062/081), not bolted onto the live ports.
- **Reviews (ios-architect + motion-red-team): no blocker shipped.** motion-red-team's false-PASS
  blocker (missing regularity signal) + the carried-vs-shaken and activity-confidence gaps are
  addressed above; the mid-stream-drop fake + test + throw-is-terminal contract close the false-FAIL
  trace. ios-architect's validation finding is the documented deferral; port independence, `async`
  availability, and #27 fail-closed decode were confirmed correct.

### WG-061 (2026-08-07): Motion & Fitness permission flow

- **The flow.** `MotionChallengeAuthorizationCoordinator` (pure, in `MotionDomain`) over a
  domain-owned `MotionAuthorizing` port, returning a closed `MotionChallengeAuthorizationStep`. It
  mirrors WG-025's AlarmKit auth flow: reads/requests the shared Motion & Fitness grant and decides
  the next step; it touches no alarms, motion samples, or persistence — so a denial/interruption can
  only *route*, never weaken or skip a challenge. Placed in `MotionDomain` (there is no
  `MotionApplication` module; it's pure decision logic over a port — ios-architect confirmed).
- **Requested in context.** `currentStep()` never prompts (reading state can't trigger the system
  dialog); only `requestAfterExplanation()` calls `requestAuthorization`, and `.notDetermined` routes
  through `.explainThenRequest` so the request follows the specific purpose copy. Whether the
  explanation *screen* was shown is the permission-UI's contract — the flow can't observe it (same
  accepted limitation as WG-025).
- **Never trap (the safety core).** Every non-authorized outcome routes to the accessible
  alternative: `denied` → offer-Settings + alternative; `restricted` → alternative (a Settings link
  can't lift a policy control); interrupted/thrown → alternative (never an assumed denial);
  still-`notDetermined`-after-request → alternative (no re-prompt loop). A user who declines Motion &
  Fitness can always still turn their alarm off (#21, SCOPE §2.3).
- **Authorization ≠ hardware present.** `.useWalkChallenge` means the app-wide grant allows motion; it
  does **not** imply the pedometer hardware exists. The E04 challenge runtime must re-check the
  per-source `availability()` (WG-060) and fall back to the accessible alternative on `.notPresent` /
  `.temporarilyUnavailable` before committing the user to a walk — documented on the step;
  enforcement is WG-063+.
- **Specific purpose copy (#41).** `MotionChallengePurpose.explanation` names the exact use
  (steps/movement for the wake walk), disclaims **location** *and* **saved workouts / health
  records** (the app reads the activity/pedometer API but never HealthKit workout records), and
  discloses the accessible alternative — no over-claim in either direction.
- **Reviews (motion-red-team + ios-architect): no blocker.** Both confirmed the never-trap property,
  the correct layering, concurrency cleanliness, and the fail-closed catch shape. Applied: the
  `notPresent` doc note, the copy-honesty tightening, and the restricted / no-loop / unknown-decode
  tests.
- **Deferred (handoffs).**
  - **Settings-opening is decide-only** here (the step signals "offer Settings"; the UI opens it) —
    `SettingsOpener` lives in `AlarmApplication` and `MotionDomain` must not depend on it. When the
    real opener lands, **hoist it to a shared cross-cutting location** so both auth flows reuse one
    (permission-center handoff, cf. WG-025 / WG-036).
  - **An explicit "try again" affordance** for an interrupted request — the status stays
    not-determined, so re-invoking retries; the affordance itself is the permission UI's job.
  - Localization of the purpose copy (E11).

### WG-062 (2026-08-07): Historical pedometer adapter

- **A separate bounded-window port.** `HistoricalPedometerSource` (domain, `MotionDomain`) is the
  awake-inference read — a cumulative step query over a validated `PedometerQueryWindow` — kept
  distinct from WG-060's live `PedometerSource` stream, as the WG-060 ADR planned. The real
  `CMPedometer`-backed adapter is an `actor` in `MotionInfrastructure`; `MotionDomain` stays
  Foundation-only (verified by `domain_no_apple_frameworks`).
- **This is where WG-060's deferred validation lands.** Untrusted CoreMotion data is validated at the
  adapter boundary: the **window** must be finite, ordered, not-future, and bounded (`maxSpan`, 24h);
  the **sample** must have a finite timestamp *inside the queried window*, a non-negative step count,
  and finite/non-negative distance/cadence/interval. A window can't read the future or an unbounded
  range, and a corrupt reading never reaches wake logic (acceptance: "queries validate intervals and
  timestamps"). The pure window/sample/availability/status logic is unit-tested in `MotionDomain`;
  the `CMPedometer` call itself is device-only (real-device checklist / **UAT CP-C**).
- **Concurrency (reviews confirmed sound).** The actor owns the non-Sendable `CMPedometer`; the
  one-shot query bridges `queryPedometerData`'s completion via `withCheckedThrowingContinuation`. The
  continuation is resumed **exactly once** on every path (the checked variant traps a hypothetical
  double-callback rather than corrupting), and the completion closure touches only `Self`-static pure
  functions + the local continuation — **no actor-isolated state**, so the CoreMotion callback thread
  races nothing (ios-architect verified definitively).
- **#41 — no raw samples, one coarse failure.** The raw `CMPedometer` error is discarded (`_`); every
  boundary failure — nil data *and* a non-nil-but-corrupt reading — maps to the single coarse
  `MotionSourceError.unavailable(.temporarilyUnavailable)` the port contract promises, so a consumer
  never sees a foreign `MotionQueryError` and the validation reason string (which names sample
  values) never escapes the adapter. An unavailable/denied source **throws**, never returns `[]` (a
  silent empty would read downstream as "user was still" — #21/#24).
- **Reviews (privacy-security + motion-red-team + ios-architect).** Privacy: **clean** (no
  raw-sample/error logging, minimal retention, bounded window). Applied the valid findings:
  - **B1 (blocker):** a NaN `now` slipped past `end <= now` (`Date` comparison is NaN-blind), so a
    finiteness guard now runs first — closes a future-read hole nothing else caught.
  - **S1:** the sample timestamp is now validated against the window it answered (a future-stamped
    aggregate would be a false "just moved" signal).
  - **Fail-open (motion + architect):** a validation throw used to propagate raw out of a port that
    promises `MotionSourceError`; the adapter now remaps it to the coarse error (fail-closed +
    tightens #41).
  - **Cancellation (architect):** `Task.checkCancellation()` fails fast if the task is already
    cancelled before the query starts.
- **Deferred (with rationale).**
  - **Quality stays `.high` for the historical aggregate.** `CMPedometer` history is authoritative
    when it answers; coverage-vs-genuine-zero can't be distinguished from the API, so the
    awake-inference consumer (E05) weights by recency/window span — it holds the window — rather than
    this adapter guessing a lower confidence. Revisit if the consumer needs a coverage signal.
  - **No absurd-but-finite plausibility caps** (e.g. a cadence ceiling). Rhythmic-tap vs gait is the
    *live-stream regularity* discriminator's job (WG-063 / WG-069 / WG-070) using
    `secondsSinceLastStep`; a scalar cap here would risk rejecting legitimate edge readings without
    catching the real cheat.
  - **The in-flight one-shot query is uninterruptible** — a historical `queryPedometerData` has no
    `stop…` counterpart, so cancellation can only fail-fast *before* the call, not tear down a call
    already in progress. Accepted; the caller's timeout still fails closed (alarm stays active).

### WG-063 (2026-08-07): Live pedometer adapter

- **CoreMotion behind an injectable seam.** The live `PedometerSource` adapter
  (`CoreMotionLivePedometerAdapter`, `MotionInfrastructure`) drives a `LivePedometerUpdates` port
  (domain) instead of `CMPedometer` directly, so the streaming, dedup, and **cancellation**
  composition is exercised off-device with a fake — only the `CMPedometerData` → `PedometerReading`
  mapping (`CMPedometerLiveUpdates`) is device-only. This is the architecture rule ("wrap Core
  Motion behind protocols") paying off: WG-063's three acceptance criteria (cancellation-safe,
  duplicate/out-of-order handled, trace tests) become real automated tests, not device-only claims.
- **The normalizer makes the non-monotonic stream ordered.** The port contract says its stream is
  *not* monotonic/fresh and names WG-063 as the layer consumers rely on to reject stale/out-of-order
  samples. `LivePedometerNormalizer` (pure, domain, value-semantics → trace-testable) drops a
  reading that is implausibly future, non-advancing (duplicate / out-of-order), a cumulative-count
  regression, or invalid (WG-060's deferred `validated`), advancing its watermark **only on a
  successfully emitted sample**. A single corrupt live reading is *dropped, not fatal* — one glitch
  can't end a walk challenge.
- **Cancellation-safe (reviews confirmed).** `samples()` sets `continuation.onTermination` (→
  `updates.stop()`) **before** starting updates, so `stop()` runs exactly once on cancel, normal
  finish, and the error path, and CoreMotion updates never leak; the unavailable early-return starts
  and stops nothing. A stream error `finish(throwing:)`s (never a plain empty completion a consumer
  could misread as "walk finished, no steps") — fail-closed (#21/#24).
- **Concurrency.** The `@Sendable` CoreMotion callback is synchronous, so it can't hop to an actor
  without a detached `Task` that would reorder deliveries and break the watermark; instead the
  normalizer lives in a `Mutex` (`import Synchronization`) — `accept` reads+advances the watermark
  atomically under one lock, and the sample is yielded *outside* the lock. ios-architect verified: no
  data race, monotonic even under hypothetical concurrent callbacks (and `CMPedometer` delivers
  serially anyway), `stop()` exactly-once, actor genuinely unusable here.
- **#41.** The raw `CMPedometer` error is discarded — a stream error surfaces only as the coarse
  `MotionSourceError.unavailable(.temporarilyUnavailable)`; an invalid reading is dropped via `try?`
  so the discarded `MotionQueryError` (whose reason could name values) never escapes. privacy-security
  review: **clean**.
- **Reviews (ios-architect + motion-red-team + privacy-security).** Applied the valid findings:
  - **B1 (blocker):** a finite *far-future* timestamp passed (the `validated` future-check only runs
    for a *windowed* historical query; the live path passes `window: nil`). It read as a false "just
    moved" **and poisoned the watermark** — jumping `lastEmitted` to the future silently drops every
    later real reading. Fixed with a `now + maxFutureSkew` guard in the normalizer (the adapter
    already injects `now`), rejecting it before it can advance the watermark.
  - **S1:** a monotonic-timestamp reading with a *decreasing* cumulative step count (a mid-episode
    reset/glitch) would hand the consumer a negative progress delta; the normalizer now also drops a
    step-count regression. (Anti-*replay* of duplicates stays WG-070.)
  - **S2:** softened an over-claim — an all-drop stream emits nothing, but "→ fails closed" is the
    *consumer's* timeout (WG-068/069) to guarantee, not this layer's; the comment now says so.
  - **Hardening (ios-architect):** `CMPedometerLiveUpdates` confines start/stop to a serial
    `DispatchQueue`, making its `@unchecked Sendable` a *structural* guarantee and ordering a rapid
    start-then-cancel so `stopUpdates` can't precede its `startUpdates`.
- **Deferred handoffs (documented).** `quality` is a uniform `.high` for live samples — the
  shake-vs-walk discriminator is the inter-step *regularity* series (WG-069/070), not a per-sample
  scalar. `secondsSinceLastStep` is **unavailable** from CMPedometer live data (only a smoothed
  `currentCadence` exists), so it is nil from this path; WG-069/070 reconstruct cadence regularity
  from timestamp deltas + cadence or `DeviceMotionSource`.

### WG-064 (2026-08-07): Motion activity adapter

- **CoreMotion behind a seam, mapping in the domain.** The live `MotionActivitySource` adapter
  (`CoreMotionActivityAdapter`, `MotionInfrastructure`) drives a `MotionActivityUpdates` port so the
  streaming + cancellation composition is tested off-device; only the `CMMotionActivity` →
  `MotionActivityReading` mapping is device-only. `CMMotionActivity` has no public initializer, so —
  as with WG-063 — the seam yields a **framework-neutral reading** (the classifier flags + confidence
  + start date) and the *testable* resolution to a single domain kind lives in `MotionDomain`.
- **Conservative kind resolution (the safety core).** `resolvedKind`: an explicit `unknown`
  dominates; otherwise exactly one flag yields that concrete kind; **0 or ≥2 flags → `.unknown`**. A
  multi-flag transition (e.g. walking + automotive) is never reported as a confident single class.
  This fails safe for the anti-cheat — the risk is a *false* "walking" letting a still user pass, so
  ambiguity resolves to the non-passing `.unknown`; under-claiming a real walk only makes the
  challenge harder (fails closed), never traps a legitimate walker on its own (a genuine steady walk
  emits single-flag `.walking`, and WG-068/069 aggregate over a window). Confidence maps 1:1 to
  `quality` (`@unknown default → .low`); the adapter **never gates on confidence** — a low-confidence
  `.walking` reaches the consumer intact so WG-068/069 own the threshold. Timestamp is retained; a
  non-finite one is dropped.
- **Stateless → no lock; freshness is the consumer's job.** Unlike the pedometer stream, activity is
  not cumulative — there is no watermark, so `samples()` holds no shared mutable state and needs no
  `Mutex`. Consequently there is **no future/stale-timestamp guard here** (WG-063 needed one only to
  stop a far-future stamp poisoning its watermark; there is no watermark to poison). The port
  contract already assigns stale/out-of-order rejection to the consumer, and a stateless mapper
  leaves the raw timestamp intact for WG-067 to window — adding a clock here would be lossy for no
  benefit. **Handoff:** WG-067 (episode builder) MUST include a future/stale-timestamp rejection test
  (the WG-063 B1 analog) — WG-064 correctly declines to be that guard.
- **Degrade safely.** `forMotionActivity` mirrors `forPedometer` (both read the shared Motion &
  Fitness grant): an unsupported device (no activity classifier) → `.notPresent`, unauthorized →
  `.notAuthorized`/`.restricted`. The adapter **throws** on any non-`.available` state before starting
  updates — a denied/absent classifier never yields an empty stream a consumer could misread as "no
  activity = stationary/asleep" (#21/#24). Auth mapping reuses `CoreMotionHistoricalPedometerAdapter
  .map` (both managers return the same `CMAuthorizationStatus`).
- **Concurrency (ios-architect: sound).** The `CMMotionActivityUpdates` seam is `@unchecked Sendable`
  with two queues: a serial `controlQueue` that orders `start`/`stop` (so they never race and a rapid
  start-then-cancel can't stop before it starts — making the `@unchecked` structural), and the
  `OperationQueue` CoreMotion delivers callbacks on. Concurrent delivery is harmless because the map
  is stateless and `continuation.yield` is multi-producer-safe, so the delivery queue is left
  default rather than forced serial. Cancellation is the WG-063 shape: `onTermination`→`stop()` set
  before start, exactly-once, unavailable path starts/stops nothing.
- **Reviews (motion-red-team + ios-architect; privacy not re-run).** Both **no blocker**. Privacy is
  a strict subset of WG-063's clean result — no numeric samples, zero logging, only a coarse
  classification + confidence — so it was not re-reviewed; no raw activity or CoreMotion state is
  logged (#41). Applied the two convergent hardening findings as tests (no production change): a
  low-confidence `.walking` survives the adapter un-dropped (locks the no-confidence-gating contract),
  and a reading delivered *after* cancellation is a safe no-op (yield-after-finish is dropped).
- **Deferred (documented).** Collapsing a multi-flag reading to `.unknown` discards *which* flags were
  set (walking + running both lost); acceptable because the port kind is single-valued and the loss
  is toward the safe `.unknown`. If a future "on-foot regardless of walk/run" inference needs it,
  widen the reading exposure at WG-067 rather than making WG-064 emit a kind it isn't sure of.

### WG-065 (2026-08-07): Device-carried & pickup evidence

- **A pure classifier, not an adapter.** `DeviceMotionEvidenceAnalyzer.evaluate` (domain,
  `MotionDomain`) infers a `DeviceMotionCharacter` — `stationary` / `pickup` / `irregularShaking` /
  `insufficient` — from a bounded window of `DeviceMotionSample`. It makes no framework calls and
  reads no clock; the CMDeviceMotion adapter (or the challenge runtime) supplies the window. This is
  supporting evidence only — a movement inference alone never suppresses an alarm.
- **Does not claim physical displacement (the honesty invariant).** CMDeviceMotion exposes
  acceleration, rotation, and a gravity-orientation scalar but never position; integrating
  acceleration into a distance is drift-dominated garbage. The analyzer only ever takes `.max()` of
  magnitudes and a gravity-angle spread/net-change — it never sums a magnitude over time, and the
  output type has **no distance/position field**. It classifies *how* the device moved, never *how
  far* (red-team confirmed by source scan: no integration anywhere).
- **Conservative, anti-cheat ordering.** Checked stationary → shaking → pickup → insufficient. A
  `pickup` requires a clear *settled net reorientation* (gravity angle moved and stayed) **and**
  non-violent acceleration; a shake is checked first, so an ambiguous/forceful motion can never be
  credited as a carry. A forceful reorientation (violent grab) falls through to `insufficient`. Every
  non-classifiable case — too few samples, non-finite magnitude, missing orientation, ambiguous —
  returns `insufficient`; the function is total (never throws/traps) and fails a challenge on its own
  never (the accessible fallback lives in the challenge layer, #21).
- **Reviews (motion-red-team; privacy/architecture not run — no surface).** No blocker: the shake
  ≠ pickup property and the displacement invariant both hold. Privacy/concurrency/persistence have no
  surface here (a pure Foundation function, no I/O, no logging, no shared state), so those reviews
  were not run. Applied the two SHOULD-FIX findings:
  - **A2a:** `netAngleChange` used the raw first/last angle, so a single glitched endpoint sample
    could manufacture a false `pickup`. It now uses a **head/tail median** (≥3 samples) that rejects
    a lone outlier; the raw min/max range stays glitch-inclusive because a wide range only biases
    toward the conservative shaking/insufficient, never a false pickup.
  - **A1 (documented limitation, not a bug):** a slow deliberate hand-tilt (reorienting the phone
    without getting up) is indistinguishable from a real pickup and is intentionally `.pickup`. The
    `.pickup` doc now states this and that a consumer must treat it as weak carry evidence only —
    **never as walking or displacement** — and a test pins the slow-tilt input to `.pickup`. The real
    wake gate is WG-069's ten-second walking verification; WG-069's author must not read `pickup` as
    a walk.
- **Battery (device-measured).** "Battery cost is measured" can't be satisfied in CI. The design
  keeps it cheap — the analyzer works on a **bounded window** (`minSamples`), so it needs only a
  short burst of device-motion sampling, not continuous high-rate updates. The actual CMDeviceMotion
  battery cost at the chosen rate/window **and** on-device calibration of the (deliberately cautious)
  default thresholds are deferred to the WG-065 real-device checklist.

### WG-066 (2026-08-07): Optional altimeter evidence

- **Supporting-only, enforced by the type.** `AltitudeEvidenceAnalyzer.evaluate` (domain) classifies
  a window of `AltitudeSample` into `unavailable` / `insufficient` / `flat` / `significantChange`. The
  enum deliberately has **no "fails a challenge" case** — `corroboratesMovement` is true for exactly
  one case (`significantChange`) and false for every neutral case — so an absent, flat, or drifting
  altimeter can only ever *fail to add* positive corroboration, never subtract. That structurally
  satisfies "altimeter is supporting evidence only" and "unavailable barometer has no negative
  impact" (every non-`.available` state maps to `.unavailable`).
- **Drift doesn't pass — with an honest caveat.** A `significantChange` requires **both** a real
  magnitude (`minSignificantChange`, 0.8 m) **and** a real rate (`minChangeRate`, 0.1 m/s). *Slow*
  weather/HVAC drift moves little over a short window and slowly over a long one, so it clears at most
  one and stays `.flat` (the tested anti-cheat). Red-team's honest correction (S1): a *fast step*
  transient — a slammed door, an HVAC kick, a nearby elevator — can clear both, and **barometry alone
  cannot distinguish it from a stand-up**. That is inherent to the sensor, which is why this is *weak*
  evidence. **Integration constraint / handoff:** WG-067/069 must never pass a challenge on a lone
  `.significantChange`; it may only corroborate independent accel/pedometer movement. Documented on
  the case and the analyzer.
- **Robust, direction-agnostic, total.** Net change uses **head/tail medians** (reject a single
  spike), clamped to *disjoint* windows so they can't overlap and halve the measured span at the
  minimum sample count (review S2). A change up *or* down corroborates (both are physical movement).
  The function is total — empty / too-few / non-finite / zero-duration windows all return a neutral
  case; it never throws or traps (#21).
- **Reviews (motion-red-team; privacy/architecture not run — no surface).** No blocker. Pure
  Foundation logic with no I/O, logging, concurrency, or persistence, so only the anti-cheat/classifier
  was reviewed. Applied: **S2** disjoint-endpoint clamp, **S1/N1** doc honesty (fast step transients +
  the downstream cross-check constraint), and a `.temporarilyUnavailable` test case.
- **Deferred.** **N2** (no sanity cap on an absurd-but-finite altitude): harmless for WG-066 — an
  over-claimed `.significantChange` is still only weak, non-failing corroboration that downstream
  cross-checks, and a cap risks rejecting a legitimate multi-floor stairs climb. On-device threshold
  calibration is on the WG-066 checklist. Uses the derived `relativeAltitudeMeters`, not raw pressure
  (data minimization; the relative altitude is CMAltimeter's own conversion).

### WG-067 (2026-08-07): Movement episode builder

- **The E04 synthesis point.** `MovementEpisodeBuilder.build(merging:now:)` (domain) merges neutral
  `MovementObservation`s from multiple sources onto one timeline and segments them into
  `MovementEpisode`s. A `MovementObservation` (timestamp + `isMoving` + optional `cumulativeSteps` +
  `source`) is what each source maps into: a live pedometer sample is movement (WG-063 only emits
  while stepping, so a stop is an emission gap), and an activity sample is movement only when the
  classifier is confidently on-foot (walking / running). Pure, deterministic; the challenge runtime
  supplies the observations + `now`.
- **This is where the deferred freshness gate lands.** Merge = flatten every stream + sort by
  timestamp (Swift's stable sort resolves cross-source interleaving and equal timestamps). The single
  filter drops any observation that is non-`isMoving`, non-finite, **stale** (older than
  `now - staleHorizon`), or **future** (later than `now + maxFutureSkew`) — the future/stale rejection
  WG-064 explicitly deferred to the builder, applied here independently of any one source's guard.
- **Pauses, resets, bed-vs-walking.** A gap larger than `pauseGap` ends an episode, so continuous
  walking forms one sustained episode while intermittent bed movement forms only short (or dropped)
  ones — the tested canonical pair. Cumulative step totals are **reset-safe against inflation**:
  `steps(in:)` *freezes* on a counter decrease rather than re-adding a fresh climb, so no interleaving
  of resets can inflate it (review S1 — `[100,5,105,5,110]` yields 0, not 205). `stepCount` is
  **advisory**, not an anti-cheat gate.
- **Reviews (motion-red-team; privacy/architecture no surface).** Fixed the one **BLOCKER**:
  - **B1:** a NaN `now` made the stale/future bounds NaN, and `Date`'s NaN-blind comparisons let
    *every* observation pass — silently disarming the freshness gate this task owns. Now fails closed
    (`guard now…isFinite`), same Date-NaN lesson as WG-062/063.
  - **S1:** freeze-on-reset step accounting (above) + corrected the docstring that had overclaimed
    "neither inflate nor deflate".
  - **S2 (doc):** a sparse injected/replayed "episode" (one sample per pause-gap) is a real
    downstream concern, but `observationCount` relative to `duration` already exposes the mean
    inter-observation gap, so WG-069 can reject a fabricated sustained episode from the emitted fields
    without re-deriving the timeline — documented on `MovementEpisode`.
  - **N2 (doc):** warned that a future `from(altitude:)` / `from(deviceMotion:)` mapper must never set
    `isMoving = true` from a lone altitude/pickup signal — that is supporting-only (WG-065/066); the
    "lone altitude never passes" invariant holds by construction today (no such mapper exists).
- **Handoffs.** WG-069 owns the cadence-variance anti-cheat and the *duration + density* gate — an
  emitted episode is not by itself "movement-grade" (`minEpisodeObservations` is only a noise floor,
  and a 2-observation episode can span up to `pauseGap`); WG-069 applies the ≥10 s and density
  thresholds. On-device segmentation calibration (`pauseGap` / `staleHorizon`) is deferred to the
  challenge.

### WG-068 (2026-08-07): Wake challenge state machine

- **A pure deterministic state machine.** `WakeChallengeMachine` (domain, Foundation-only) holds a
  `WakeChallengePhase` (idle / starting / active / passed / failed / timedOut / unavailable) + a
  `ChallengeProgress`, advanced by `apply(_ event)`. Only enumerated `(phase, event)` pairs
  transition; **every other event is a no-op** returning `false` (state never corrupted) — "only
  valid transitions are possible". It reads no clock and makes no framework calls (the caller injects
  `.timeout` / `.observedProgress`), and it **cannot call AlarmKit or mutate persistence** — it only
  *reports* a phase the alarm layer acts on.
- **The safety core.** `permitsAlarmDismissal` is true for **`.passed` only**; every non-pass
  terminal (failed / timedOut / unavailable) and every non-terminal phase keeps the alarm active
  (#21, SCOPE §2.3). Terminals are stable — only a deliberate `.reset` (re-arm) leaves them, so a
  late `.observedProgress` / `.sensorsReady` can never flip a timed-out/failed challenge to
  passed/active. `.unavailable` is reachable from idle/starting/active so a dropped sensor always
  routes to the accessible alternative, never traps.
- **Inflation-proof progress (the redesign).** `ChallengeProgress` is `peak − baseline` over the
  **cumulative** counts observed during the run — a pure function of the peak. This is monotonic and
  **inflation-proof by construction**: a replayed/duplicate value can't raise the peak, and a counter
  reset (a dip) can't add (a later climb only counts once it passes the prior peak). It matches the
  motion stack's contract (`PedometerSample.stepCount` is cumulative, "robust to duplicate/replayed
  samples so they cannot inflate it"). A pause clears baseline+peak (a safe zero reset); `required`
  is clamped ≥ 1 so a degenerate target can't auto-pass.
- **Reviews (alarm-safety-reviewer + motion-red-team — both, safety-critical).** Both confirmed the
  only-`.passed`-dismisses invariant, terminal stability, and determinism. Both independently found
  the same two defects in the first cut, now fixed:
  - **BLOCKER:** the original additive `advance(by: delta)` computed `completed + delta` — a checked
    add that **traps on overflow** for a near-`Int.max` delta, crashing the challenge on the
    dismissal path (can't run the safe fallback; violates "no traps in production"). The peak−baseline
    form uses `subtractingReportingOverflow` and **saturates at `required`**, never traps.
  - **SHOULD-FIX:** `observedProgress(Int)` was a *trusting raw delta*, making replay/inflation
    representable (N replays each add). Changed to `observedProgress(cumulative:)` + peak tracking, so
    double-counting is unrepresentable regardless of how WG-069 feeds it. Added adversarial tests
    (replay, reset-spam, `Int.max` saturation).
- **Handoffs.** WG-069 feeds `.observedProgress(cumulative:)` from *verified* movement episodes
  (WG-067) and drives `.timeout`; it owns the cadence-variance anti-cheat and the duration/density
  gate. **WG-073 (ring-stop) must gate alarm dismissal on `permitsAlarmDismissal` (a valid terminal
  `.passed`)** — never on a raw notification action or a stale Live-Activity button (#24) — flagged by
  alarm-safety as a downstream review item.

### WG-069 (2026-08-07): Ten-second walking verification

- **What it verifies.** `WalkVerifier.verify` (domain) checks whether any `MovementEpisode` (WG-067)
  is a *validated sustained walk* against `WalkRequirements`, applying three conjunctive gates:
  **duration** ≥ the ten-second floor (a short movement fails), **step count** ≥ a floor (a
  device-only stationary pickup with no real steps fails), and **density** — mean inter-observation
  gap ≤ the bar (a sparse injected/replayed episode fails). Pure, deterministic, Foundation-only.
- **Configurable within safe bounds (one-directional clamp).** `WalkRequirements` clamps every
  threshold so a challenge can be made *stricter* but **never weaker** than the safe floor: duration
  ∈ [10, 120], steps ∈ [10, 200], mean-gap ∈ [0.2, 2.0]. A lenient / negative / zero / `NaN` /
  `Infinity` / overflowing config is clamped or falls to the field's safe default (duration→10,
  gap→2.0) — a mis-set or adversarial config **cannot** create a trivially-passable challenge. The
  ten-second floor is guaranteed (alarm-safety verified across a hostile input matrix).
- **#21 — a movement inference alone never fails.** `WalkVerification` has only `.passed` /
  `.insufficient` (no `.failed`): the verifier can only *confirm a walk* or say *not yet*, and the
  timeout (WG-068) is what turns "not yet" into a kept alarm. It reads no clock, calls no framework,
  and cannot dismiss/suppress an alarm — it returns a verdict only. The accessible non-walking
  fallback is orthogonal and untouched.
- **Reviews (motion-red-team + alarm-safety-reviewer — both, safety-critical).** Alarm-safety: **no
  false pass**, the ten-second floor cannot be weakened, determinism and the accessible alternative
  confirmed (27 hostile probe tests). Applied the findings:
  - **B1 (honesty blocker):** the first cut's comments called this "the anti-cheat culmination" and
    claimed "a shake fails". That is **false** — CMPedometer counts shake accelerations as steps and
    WG-067 treats every pedometer sample as movement, so a **sustained regular-cadence shake that
    yields pedometer steps clears all three gates** (it isn't short, stepless, or sparse). Step
    *regularity* is not measured here. Corrected the docs to say plainly that WG-069 gates the
    *trivial* fakes and that the shake / replay defense — cadence regularity — is **WG-070's** job
    (backlog: "rapid irregular motion without pedometer evidence fails"). **This threat is NOT closed
    by WG-069.**
  - **S3 (fail-closed):** `isValidWalk` now guards `duration.isFinite && >= 0` first, so a
    corrupt/negative-duration episode fails independent of the producer's invariants.
  - **S1/S2 (doc reconciliation):** noted that `stepCount` is WG-067's *advisory* count used here
    only as an **inflation-proof lower bound** (can't be fabricated upward → a stepless pickup fails),
    and that the mean-gap gate is a *coarse backstop* (WG-067's `pauseGap` already caps any single
    within-episode gap; true regularity is WG-070).
- **Handoffs.** **WG-070** owns the regular-cadence shake + replay defense (the headline anti-cheat).
  The task that wires WG-069 into WG-068 must map `.insufficient` to "keep waiting / let the timeout
  fire", **never** to a failure or a stop command (both reviewers flagged this integration contract).

### WG-070 (2026-08-07): Anti-shake & replay defenses

- **The cadence-regularity model.** `CadenceRegularity` (domain) reconstructs the inter-step interval
  series from `MovementObservation` cumulative step counts (the live pedometer exposes no per-step
  interval, WG-063) and classifies it: `.plausibleGait` (the only case that corroborates a walk) vs
  `.tooFewSteps` / `.implausibleTiming` (a per-step interval outside [0.25, 1.2] s) / `.tooErratic`
  (coefficient of variation > 0.5) / `.tooRegular` (CV < 0.03). Pure and deterministic.
- **Acceptance met — rapid *irregular* motion fails.** Verified: an alternating `[0.3, 1.1, …]`
  series → `.tooErratic`; a bursty shake (`[0.2, 1.0, 0.167, …]`) → `.implausibleTiming`. **Duplicates
  can't inflate:** reconstruction skips any segment with Δsteps ≤ 0 (a duplicate or reset contributes
  no interval — 20 duplicate samples padded onto a real walk still yield too few intervals), and a
  constant-cadence (metronomic) replay → `.tooRegular`.
- **Honest limitations (disclosed, not silent — acceptance criterion 3).** This is a *first-moment*
  (CV) model and it is **corroboration, not a standalone pass** — SAFETY_INVARIANT #19/#20 hold at the
  *system* level because a dismissal requires multiple independent signals and the timeout keeps the
  alarm; a rejection here is never authoritative. Within that frame, the accepted residuals are:
  - **A *regular* / paced shake passes** (review S1). A human shaking rhythmically at ~2/s with hand
    jitter lands CV ≈ 0.065 — inside the plausible band; a CV-only model cannot separate it from a
    gait. The literal criterion ("rapid *irregular* motion fails") is met; the *regular*-shake fix is
    deferred to the WG-075 on-device calibration study. Pinned by `testPacedShakePassesAsKnownLimitation`
    so it can't change silently.
  - **Exactly-periodic alternation is accepted** (S2). CV is order-blind, so `[0.4, 0.6, 0.4, 0.6, …]`
    (a tap/replay signature) reads as `.plausibleGait`. A periodicity / autocorrelation gate is
    out of scope for the MVP CV model → WG-075.
  - **Jittered fabricated replay isn't defeated here** (S3). A monotonic fabricated stream with
    hand-like jitter passes; that is the adapter's *injection-trust* boundary (WG-063), not a cadence
    property. Only duplicate/reset and constant-cadence replays are defeated by this statistic.
  - **`minimumIntervals = 8` is coupled to CMPedometer's ~1 Hz delivery** (S4): a genuine 10 s walk
    yields ~9 intervals, so slower/batched delivery could false-reject a real short walk. Calibratable
    (WG-075). Population variance (`/n`, N1) is marginally permissive; calibration accounts for it.
- **False-positive set (corrected — S5).** The specific real walkers this *rejects*: a steady
  **treadmill** walker (near-constant cadence → `.tooRegular`), a **slow / elderly** gait slower than
  1.2 s/step (→ `.implausibleTiming`), and any very-regular walker. Each is tolerable **only** because
  the rejection is non-authoritative and the **accessible alternative is always available** (#21/#22).
- **Review (motion-red-team).** Confirmed rapid-irregular-motion fails and duplicates can't inflate;
  no safety invariant violated (every rejection is non-authoritative; the accessible fallback is
  untouched). Applied: corrected the false-positive docstring (a limp actually *passes*; treadmill /
  slow-gait are the real rejections), corrected the replay-scope claim, and added the paced-shake
  limitation test. **Handoffs:** WG-071/073 wire the verdict into the challenge (not consumed yet);
  **WG-075** owns the device calibration + the periodicity/regular-shake follow-up. The system "shaking
  alone cannot pass" guarantee (#20) rests on multi-signal corroboration (#19), not on this file alone.

### WG-071 (2026-08-08): Challenge UI & progress feedback

- **The in-progress challenge screen over WG-068.** `ChallengeView` presents `ChallengeViewModel`,
  which drives the deterministic `WakeChallengeMachine`. The **view model is Foundation-only** (plain
  display values + neutral haptic-cue intents) so all display/cue logic is unit-tested; the view owns
  all SwiftUI/UIKit. The VM **reports**, it never dismisses — the alarm's active state comes straight
  from the domain.
- **Safety (both reviewers: HOLDS, no blocker).** `isAlarmActive = !phase.permitsAlarmDismissal`, so
  the alarm reads **clearly active for every phase except `.passed`** (#21); the copy for
  timedOut/failed/unavailable explicitly says "the alarm is still active", never implies it's handled.
  The accessible non-walking alternative is offered for every non-passed phase (**never a dead-end**),
  and its action closure is **non-defaulted** — a caller that forgets to wire it is a *compile error*,
  not a silent dead-end button (alarm-safety hardening). The VM cannot force `.passed` (the machine's
  guarantee) and the pass haptic is cosmetic.
- **Sleep-inertia legibility + accessibility.** Big plain progress (a bar + a large "X of Y steps")
  with an imperative headline ("Walk to turn off the alarm"). Meaning is **never color-alone** — a
  distinct label + SF Symbol per phase, tint reinforcing only. **VoiceOver:** live announcements are
  *posted on change* (a terse count on a step milestone, the full status on pass / not-pass) so a
  groggy, not-looking user is actually told what happened — plus a clean label/value split
  (`Walk progress` / `6 of 12 steps`) and `.updatesFrequently`. **Dynamic Type:** semantic fonts in a
  `ScrollView` with the fallback button pinned via `safeAreaInset`, so nothing truncates and the
  alternative is always reachable at the largest sizes. **Reduce Motion** gates the bar animation;
  colors are system-semantic (dark mode / Increase Contrast).
- **Haptics.** Neutral `ChallengeHapticCue` intents (VM, testable) → the view's feedback generators.
  Progress haptics are **throttled to quarter milestones** (no fatigue / no competing with the alarm's
  own feedback); `.passed`/`.notPassed` stay crisp and rare.
- **Reviews (ux-accessibility-reviewer + alarm-safety-reviewer).** No blocker. Applied the UX
  SHOULD-FIXes — VoiceOver *announce-on-change* (was a static label only), throttle per-step haptics,
  drop the redundant percent (label/value split), and `ScrollView` + pinned fallback for large
  Dynamic Type — and the alarm-safety hardening (non-defaulted alternative closure).
- **Handoffs.** WG-072 wires `onUseAccessibleAlternative` to the accessible-alternative flow
  (compile-enforced). The challenge *runtime* that feeds `apply(_:)` from live sensors is a later task.
  On-device VoiceOver / haptics / Dynamic Type / Reduce Motion verification is on the checklist.

### WG-072 (2026-08-08): Accessible challenge alternatives

- **A deterministic, input-gated runtime.** `AccessibleChallengeMachine` (AlarmDomain, Foundation-only)
  passes the *same* challenge via a deliberate manual gesture — a **debounced tap sequence** or a
  **press-and-hold**. It advances **only** through explicit user-input events (`tap` / `beginHold` /
  `holdTick` / `endHold`) with a caller-supplied timestamp; it reads no clock and has no model/AI
  seam. So — exactly as AI cannot call AlarmKit (#1) — **AI can neither invoke nor complete it** (it
  can't emit touches); `AccessibleChallengeTests` proves there is no non-input path to `.passed`.
- **Deliberate but completable, never a dead-end.** `requiredTaps` clamps to [4, 12] and taps are
  debounced (within-0.15 s / out-of-order / non-finite taps ignored), so a single accidental / stuck /
  auto-repeating touch can't pass it; press-and-hold clamps to [2, 8] s and an early release **safely
  resets** (never *fails* the challenge — the alarm stays active until genuinely passed, #21). Passing
  the alternative is equivalent to passing the walk. **Preselection without stigma** already exists in
  the create/edit flow (WG-045, default `.tapSequence`); the copy is affirming ("Another way to turn
  off the alarm"), and the VM's `onPassed` is the seam WG-073 wires to the authorized stop (the
  WG-071 entry point's closure is compile-enforced).
- **The accessible fallback is itself accessible (the ux review's two blockers, fixed).**
  - **B1:** a sustained `onLongPressGesture` is a **VoiceOver / Switch Control dead-end** (assistive
    tech intercepts touch, so the gesture never fires). Added an `.accessibilityAction` +
    `completeViaAccessibleActivation()` so an assistive-tech activation completes the hold — the
    accessible equivalent of holding, still a deliberate input (not AI-reachable), so the fallback is
    never a dead-end.
  - **B2 / S1 / S3:** the default tap path gave no per-tap feedback. Added a **big live count**
    ("3 of 6 taps") and a **per-tap VoiceOver announcement** (only on an accepted tap), so a groggy /
    low-vision / blind user knows a tap registered and how many remain. **S5:** the completion
    announcement is posted **high-priority** so it isn't clobbered by the next screen. Dynamic Type
    (semantic fonts), Reduce-Motion-gated bar, non-color, and the hold timeline is paused when not
    actively holding.
- **Reviews.** ux-accessibility-reviewer found the two blockers above (fixed) and confirmed the
  non-stigmatizing framing + deterministic anti-cheat. The alarm-safety-reviewer **timed out** before
  returning — its hostile probes (identical-timestamp taps rejected, hold requires begin, backward
  clock ignored, `onPassed` fires once, wrong-kind inert) were all *passing* when it stopped, and the
  safety property is directly encoded and covered by `AccessibleChallengeTests` (input-gating /
  AI-can't-invoke) and `AccessibleChallengeViewModelTests` (`onPassed` once, early release never
  fires); the reviewer left probe code in the test file, which was removed.
- **Handoffs.** WG-073 wires `onPassed` → authorized stop. WG-075 verifies on-device accessibility
  (VoiceOver / Switch Control completion, motor-impaired usability). Residual **B2** (a non-assistive
  tremor user could still self-select the harder press-and-hold) → the create-flow picker should
  recommend `.tapSequence`; noted for the WG-045 polish, and the always-available alternative + the
  assistive-tech completion mitigate it.

### WG-073 (2026-08-08): Connect a valid challenge pass to the authorized stop

- **The ring-stop primitive (the port doc promised it).** Added `stopRing(alarmID:)` to
  `AlarmManagerAdapter` — the authorized ring-stop, gated on a valid pass (#24), a **no-op on a
  not-ringing id** (idempotent), distinct from `cancel` (which removes a *scheduled* alarm and must
  never stop a ring). Impls: `SystemAlarmManagerAdapter` → AlarmKit `stop(id:)` (presence-checked like
  `cancel`; ios-architect confirmed `stop` is the right primitive vs `cancel`), the interim
  `DeferredAlarmManagerAdapter` → **no-op** (nothing rings yet — safe), `FakeAlarmManagerAdapter` →
  records the call.
- **`markChallengePassed` now stops the ring.** The processor's stub (which audited `.noOp`) becomes
  `applyChallengePassed`: it stops the ring through the **outbox-bracketed** `runExternal` (key kind
  `"stopRing"`), so a racing / duplicate submission **dedups on the key** (the adapter is called at
  most once) and a crash/uncertain outcome is tracked; it makes **no local mutation** (only the ring
  stops; the next occurrence still fires). The command dispatch was extracted to `apply(_:context:)`
  to stay within the cyclomatic-complexity limit (behavior-preserving — architect verified the
  non-comment diff is exactly the new case + handler).
- **The coordinator (the "connect").** `ChallengeStopCoordinator` (AlarmApplication, an `actor`)
  submits **exactly one** `markChallengePassed` through the `AlarmCommandProcessing` boundary (the only
  path to the adapter, #2) for a **terminal walk pass** (`permitsAlarmDismissal`, true only for
  `.passed`) or the **accessible fallback** — and *nothing* for any other phase (#21: a movement
  inference alone never stops the alarm). Its once-only guard flips **before** the first `await`, so
  the actor makes it race-safe exactly-once (architect confirmed: no reentrancy hole).
- **Reviews (alarm-safety-reviewer + ios-architect — both read-only, safety-critical).** No blocker;
  both confirmed **"only a valid pass stops the ring" (#24) HOLDS** and **"duplicate / racing passes
  stop once" HOLDS** (coordinator once-only + outbox dedup, tested to `stoppedRingIDs == [id]`).
  Applied the findings:
  - **A (audit honesty, #46):** an *uncertain* stop was audited `.succeeded` ("Alarm stopped") though
    the ring may still sound. Now audited **`.failed`** with an honest reason — matching the codebase's
    `auditUncertainRepair` convention. `.applied` → `.succeeded`, a definite failure → `.failed`, a
    missing alarm → `.noOp`.
  - **B (comment overclaim):** corrected "an uncertain delivery is reconciled from the outbox" — no
    reconciler re-drives a stranded `stopRing` (reconcile only does schedule/cancel from divergence). A
    not-actually-stopped ring simply keeps ringing and the user re-completes the challenge (the safe
    direction — a ring never silently looks handled).
  - **Test:** `FakeAlarmCommandProcessor.process` now has a real suspension point so the 50-task
    concurrency test genuinely exercises the actor reentrancy window.
- **Interim scope (honest).** `DeferredAlarmManagerAdapter` is what's composed today (nothing rings),
  so `stopRing` is a field no-op; the real ring-stop is live once `SystemAlarmManagerAdapter` is
  composed (WG-026). The **CONNECT half is a seam**: the challenge *runtime* (a later task) wires
  `ChallengeViewModel` (phase → `.passed`) → `coordinator.walkChallengeReached` and
  `AccessibleChallengeViewModel.onPassed` → `accessibleAlternativePassed`, injecting the right audit
  `source` (`.notificationAction` for a notification-driven pass). **Handoffs:** WG-026 must make
  `SystemAlarmManagerAdapter.map`'s reason strings **operation-aware** (a failed `stopRing` currently
  reads "could not be scheduled"); WG-029 could add stranded-`stopRing` recovery (today the re-ring is
  the fallback).

### WG-074 (2026-08-08): Motion trace recorder for internal testing

- **DEBUG-only; production excludes it.** `MotionTraceRecorder` records the WG-060 motion samples into
  a `MotionTrace` exportable as JSON for the on-device calibration study (WG-075). The whole file is
  `#if DEBUG`, so it **does not exist in the App Store archive** — privacy-security verified the
  Release build config sets no `DEBUG` compilation condition and that **no production code references**
  the recorder (nothing composes it into `AppEnvironment`). The test file is `#if DEBUG` too.
- **Anonymized traces (#41).** Each sample is **re-timestamped on capture** to a *relative* offset
  (`rebased(to:)` → `epoch + (t − base)`), so no absolute wall-clock time — which could reveal *when*
  the user slept — survives into the trace; the export encodes dates as `.secondsSince1970` so JSON
  shows offsets (`1.5`), not a wall clock. The WG-060 samples already carry only motion magnitudes + a
  single orientation scalar and **no user / device / alarm id and no location** (no raw axes). The
  recorder **logs and persists nothing** — state is in-memory and export is explicit and caller-driven.
- **Consent-gated (fail-closed).** `record` is a no-op unless the tester acknowledged `consentWarning`
  (which states what is captured, that it's anonymized, and that it's internal-only). One recorder
  instance is one consented session (consent is fixed at init; re-consent = a new recorder).
- **Residual re-identification risk (documented — privacy SHOULD-FIX).** An anonymized trace is still
  a *pseudonymous-behavioral* artifact: a gait cadence + step series can be fingerprinted against an
  external labeled reference of a known person. This is inherent to any motion-calibration trace and
  acceptable for an **internal, consented** artifact that never ships and carries no direct
  identifier — **but the exported trace must stay on-device / internal and never be distributed**, and
  its **retention (#43)** is owned by whoever holds the exported `Data` (WG-075). The caller-supplied
  `label` is a free-text run tag and must not contain PII (documented on `makeTrace`).
- **Review (privacy-security-reviewer, read-only).** **PASS, no blocker** — production-exclusion and
  anonymization both confirmed. Applied the doc findings: the one-session consent note + the `label`
  caveat on the recorder, and this ADR's residual-risk / on-device-only / retention note. **Handoffs:**
  WG-075 consumes the traces (and owns their retention); the recording *harness* (a debug UI that
  obtains consent and feeds live samples) is a debug-tooling seam.

### WG-075 (2026-08-08): Real-device calibration study

- **The study.** The motion analyzers (WG-065 / 066 / 069 / 070) ship with cautious baseline
  thresholds; this study tunes them on real hardware. The **test matrix + procedure** live in
  `docs/CALIBRATION.md`: carry positions **hand / pocket / bag**, **slow / brisk gait**, and **shake
  attempts** (rhythmic, erratic, nightstand, and the paced-shake cheat), plus still / pickup / stairs
  — each recorded as a WG-074 anonymized trace and compared to the expected verdict.
- **Threshold decision — baseline retained pending the on-device study.** The real-device study
  requires hardware + human testers and **cannot run in CI**, so the tuned values are **device-pending**.
  The decision recorded here today: the app ships on the **`CalibrationProfile.baseline`** — every
  analyzer's cautious `.default` (the individual values + rationale are in the WG-065 / 066 / 069 / 070
  ADRs). When the study runs, the chosen `CalibrationProfile` values, their rationale, and the
  **residuals** are recorded in this section. The known **paced-shake residual** (WG-070; matrix cell
  15) must be closed by requiring a *second independent signal*, **never** by loosening a threshold —
  the study is forbidden from widening a gate to force a case.
- **No participant identifiers (the safety criterion, privacy: HOLDS).** `CalibrationProfile` stores
  **only tuning parameters** + its own random-UUID `id` (a within-app foreign key, not tied to a
  person) — no name / user / device / location / timestamp / raw sample (tested structurally, incl. a
  recursive nested-key check). `WalkRequirements` **re-clamps on decode**, so a persisted / tampered
  profile can only make the walk *stricter*, never below the ten-second floor; and the advisory
  analyzers (device-motion / altitude / cadence) never gate a pass, so their un-clamped thresholds
  can't flip a non-walk to a pass (both tested). Codable was added to the four `Thresholds` types (the
  three advisory ones auto-synthesized; `WalkRequirements` custom, re-clamping).
- **Artifact sensitivity (privacy NIT).** Unlike a WG-074 *trace* (a pseudonymous gait fingerprint
  that must stay on-device / internal), the `CalibrationProfile` is a **shareable non-sensitive
  artifact** — purely numeric thresholds with no path back to a person. This distinction is
  deliberate and recorded so the two are not conflated in retention policy (#43).
- **Review (privacy-security-reviewer, read-only). No blocker** — confirmed no participant identifiers
  are stored and the walk floor can't be weakened via a decoded profile. Applied its hardenings: the
  no-participant-id test now recurses into nested keys (structural, not top-level only), a test pins
  that lenient advisory thresholds can't manufacture a pass, and this ADR records the decision (SF-1)
  and the artifact-sensitivity distinction (NIT-3). **Handoffs:** the real-device execution (tune +
  record the final profile) is device-pending; wiring an alarm's `CalibrationProfileID` → load profile
  → supply the analyzers is the challenge-runtime seam.

### WG-080 (2026-08-09): Deterministic awake-evidence model

- **What it is.** `AwakeEvidenceModel` (pure, Foundation-only, `MotionDomain`) combines the four
  signals the acceptance names — **recent steps**, a **sustained movement episode** (WG-067), how
  **recent** that movement is, and an **optional device interaction** — into an advisory
  `AwakeEvidence`: an `AwakeLikelihood` (`notEnough` / `weak` / `likely`), a numeric `score`, and the
  **per-factor contributions** (each factor + whether it fired + its weight). It opens E05 (pre-alarm
  intelligence); WG-082 will consume it to decide whether to *surface a pre-alarm prompt*.
- **Advisory only — the governing invariant (#8, HOLDS structurally).** "A movement-based *likely
  awake* inference never cancels an alarm in the MVP." `AwakeEvidence` is a pure value — three lets +
  a derived `presentFactors`, conforming only to `Sendable/Equatable/Hashable/Codable`. It carries
  **no** alarm id, command, adapter reference, or `cancel`/`suppress`/`stop` — so it *cannot* reach
  AlarmKit or persistence. Even `.likely` is just a label; the strongest reading can, at most, inform
  a prompt. (No consumer wires it yet — WG-082's seam.)
- **No single weak signal is conclusive — STRUCTURAL, not a default-weights coincidence.** The core
  acceptance property. `.likely` requires the summed score to reach `likelyThreshold` (0.6), and the
  `Config` initializer **clamps every factor weight strictly below `likelyThreshold`** (`min(weight,
  likelyThreshold.nextDown)`), so *no lone factor at any magnitude* — a phone racking up steps in a
  bag, an hours-long "episode", a fresh recency, a pickup — can ever reach `.likely`, for **any**
  caller-supplied config (pinned by `testHostileConfigCannotMakeSingleFactorConclusive`). This mirrors
  WG-075's re-clamp-on-construct: the safety property is enforced by the type, fail-closed toward "not
  awake". Default weights: steps 0.4, sustained 0.4, recency 0.25, **device 0.15** — the device signal
  is deliberately *supporting-only* (a bare pickup + one main factor stays `.weak`, so a pickup is
  never the deciding vote into `.likely`; `testDevicePickupCannotTipSingleMainFactorToLikely`).
- **Inspectable factor contributions (acceptance, HOLDS).** `evaluate` always emits a contribution
  for **all four** factors (present-or-not, with weight), plus the total `score` — a consumer can
  reconstruct exactly why the evidence read as it did (feeds the future #32 explanation UI). Nothing
  is collapsed into an opaque number.
- **Fail-closed on adversarial numeric inputs.** The raw overload sanitises before gating: a
  non-finite / negative `longestEpisodeDuration` → 0 (an `.infinity` duration must not satisfy `>=
  minSustainedDuration`), and a negative / `NaN` `secondsSinceLastMovement` → `.infinity` (a negative
  recency must not satisfy `<= recencyWindow`) — a garbage input reads `.notEnough`, never a spurious
  `.likely`. The episode-derive overload **drops future-dated episodes** from recency and sums step
  counts with **saturating arithmetic** (`addingReportingOverflow` → `Int.max`) so a hostile
  large-`stepCount` trace can't trap the process (#10; the WG-068 overflow lesson) — and since steps
  are only a ≥15 boolean gate, saturation can't inflate the score either.
- **Known limitation — passive transport reads as `.likely` (pinned, not hidden).** The model has no
  activity-class / cadence discriminator, so a phone accruing pedometer steps in a bag on a moving
  vehicle presents recent steps + a sustained episode + recency at once and reads `.likely`
  (`testPassiveTransportReadsAsAwakeKnownLimitation`). Documented per the WG-070/075 house style;
  **tolerable only because the model is advisory** — a false `.likely` can surface a prompt but can
  never suppress an alarm (#8). Closing it (a cadence/activity gate) is deferred.
- **Review (motion-red-team, read-only). No BLOCKER** — it confirmed #8 advisory-only integrity and
  inspectability hold, and that no single default-weight reaches the bar. Applied its four SHOULD-FIX
  findings: the **structural `Config` clamp** (was a default-weights coincidence), the **transport
  residual** doc + pinned test, the **raw-overload sanitisation** (∞/negative duration & recency), and
  the **saturating step sum** (was an overflow trap); plus its NIT — the device weight nudged 0.2 →
  0.15 so a pickup is never decisive. **Handoffs:** WG-081 (recent-movement history query) supplies
  the steps/episodes/recency; WG-082 (pre-alarm evaluator) consumes `AwakeEvidence` and **must treat
  `.likely` as advisory** — surface the prompt, never suppress; a later task may add the transport gate.

### WG-082 (2026-08-09): Pre-alarm evaluator

- **What it is.** `PreAlarmEvaluator` (pure, Foundation-only, `AlarmApplication` — the composition
  layer) turns the WG-080 awake evidence + the WG-081 recent-movement snapshot + the alarm's
  `Criticality` + `PreAlarmPolicy` + `timeRemaining` into a `PreAlarmRecommendation` — the E05
  capstone. `now`/`timeRemaining` are injected; it holds no state.
- **Only recommends whether to prompt (acceptance + #8, HOLDS structurally).** `PreAlarmRecommendation`
  has four fields — `reason`, `offeredActions` (a subset of the user's policy), `requiresConfirmation`,
  `evidence` — and **no** alarm id, command, adapter, or `cancel`/`stop`/`suppress`. It cannot reach
  AlarmKit, the command processor, or persistence; the strongest output is "prompt, and here are the
  actions the prompt *may* offer". So a movement inference can never directly cancel an alarm.
- **Criticality and time remaining influence the policy (acceptance).** Time gates the lead window:
  prompt only when `minimumTimeRemaining(for:) < timeRemaining <= leadTime` (inclusive upper, strict
  lower; a non-finite/negative `timeRemaining` fails closed). Criticality influences two things: (a)
  `requiresConfirmation = critical && offers a destructive action` (#6 — `turnOffToday`/`changeTime`
  are destructive, `remindLater` is not); and (b) a **more conservative imminent cutoff** — a critical
  alarm uses a larger minimum (120 s vs 60 s), so it is not nudged in the final stretch before ringing.
- **Evidence floor + #7.** Only a corroborated `.likely` prompts (`.weak`/`.notEnough` decline) — and
  WG-080 guarantees `.likely` cannot come from a single weak signal, so no lone signal ever nudges. An
  enabled policy with empty `allowedActions` still prompts but purely informationally; "keep the alarm"
  is the implicit no-op that #7 guarantees on no response.
- **`sourceAvailable` — "couldn't observe" ≠ "confirmed still".** The snapshot overload gates on
  WG-081's `sourceAvailable` **explicitly** (not on the coincidence that an unavailable source reports
  0 steps) and declines with a distinct `.sourceUnavailable` reason, so a future degraded source that
  reports steps while unavailable still can't nudge, and the reason stays honest for a later
  explanation UI (#32).
- **`leadTime` finiteness (fail-open closed).** A `leadTime == .infinity` would have collapsed the
  "too early" upper bound. Fixed at the root — `PreAlarmPolicy.enabled` now rejects a non-finite
  `leadTime` (the `Decodable` init inherits it, so a corrupt persisted ∞ fails closed) — plus a
  defense-in-depth `policy.leadTime.isFinite` guard in the evaluator.
- **Known limitation — passive transport prompts (pinned).** The MVP feeder (WG-081 aggregate history)
  gives recent-steps + recency, the exact pair passive transport corroborates, so a commute's false
  `.likely` (WG-080's residual) **surfaces a prompt** here (`testPassiveTransportStillPromptsKnown-
  Limitation`). Tolerable only because the prompt is advisory (#7/#8). Re-pinned at this surface rather
  than silently inherited.
- **Stateless — cooldown is WG-083's job (handoff).** WG-082 is deliberately stateless, so it has no
  de-dup/cooldown; a finished walk keeps reading `.likely` until it ages out of the widest recency
  rung, so **prompt de-duplication / cooldown / once-per-morning gating is a hard requirement on the
  WG-083 runtime**, not optional.
- **#6 enforcement is a hard handoff, not a convention.** `requiresConfirmation` is advisory until
  WG-083 reads it. The rule for WG-083: a destructive pre-alarm action MUST be submitted as an
  `AlarmCommand` through `AlarmCommandProcessor` (which independently gates critical cancel/delay on
  `userConfirmed`) — **never** a direct adapter call, and the flag MUST NOT be treated as optional. #6
  is thus defended in depth (the policy engine re-gates even if a consumer ignored the flag).
- **Review (alarm-safety-reviewer + motion-red-team, read-only). No BLOCKER** — alarm-safety verified
  #8 (no mutation path exists, by type), #7, #6 (flag + correct destructive classification),
  criticality×time gating, and determinism; motion-red-team confirmed the coarse recency never
  *over*-states awakeness (it's an upper bound → harder to fire) and a bare device pickup can't reach
  `.likely`. Applied: the `leadTime.isFinite` fix (fail-open), the explicit `sourceAvailable` gate +
  `.sourceUnavailable` reason, the transport residual re-pin (doc + test), the stateless/cooldown +
  #6-routing handoffs recorded here, and boundary + confirmed-still tests. **Handoff:** WG-083 owns the
  prompt notification categories/actions, the #6 confirmation enforcement (via `AlarmCommandProcessor`),
  and the cooldown/de-dup.

### WG-083 (2026-08-09): Pre-alarm notification categories and actions

- **What it is.** `PreAlarmPromptContent` (pure, Foundation-only, `AlarmApplication`) is the pre-alarm
  prompt's presentation model — the ordered buttons + the title/warning keys — built from a WG-082
  `PreAlarmRecommendation`; `PreAlarmPromptStrings` holds the development-language copy; and
  `PreAlarmNotificationCategoryFactory` (`AlarmInfrastructure`, the only file that imports
  `UserNotifications`) maps the model to a real `UNNotificationCategory` + `UNNotificationAction`s.
- **Actions as configured, keep always present (acceptance).** `keep` — the #7 no-op default — is
  **always** the first button, for any criticality and even for an empty offered set (an informational
  keep-only prompt); the user's configured actions follow in a deliberate **safe → destructive** order
  `[keep, remindLater, changeTime, turnOffToday]`, so a groggy accidental tap on the top button is the
  safe outcome and the one truly alarm-silencing action is last (and renders `.destructive`/red, with
  the label itself — not color alone — carrying the meaning).
- **Warning says the alarm remains unless amended (#7, acceptance).** Every prompt carries the warning
  ("Your original alarm stays scheduled unless you change it.") — **including the keep-only
  informational prompt** (pinned by `testInformationalPromptStillCarriesTheWarning`), the case where a
  user could most easily mistake the prompt for "already off". It is a non-optional field, so it can
  never be absent.
- **Localization-ready (acceptance).** Every displayed string is a namespaced key; the factory
  resolves action titles via `NSLocalizedString(key, value: <dev English>, comment:)`, and the
  dev-English fallback lives in `PreAlarmPromptStrings` (renamed `developmentFallback(for:)` — it is a
  fallback shim, **not** a localizer). Stable identifiers (`prealarm.action.<case>`) are separate from
  title keys and never localized, so a later response router can switch on them. E11 supplies the
  translated `.strings`.
- **#6 confirmation flag.** `requiresConfirmation` is set on a **destructive button only** (`turnOff-
  Today`/`changeTime`) and only for a critical alarm; `keep`/`remindLater` never confirm. The factory
  maps it to `UNNotificationActionOptions.authenticationRequired` — **a device-unlock gate, NOT the #6
  explicit confirmation.** The real confirmation + the mutation are the prompt runtime's job, routed
  through `AlarmCommandProcessor` (which returns `.needsConfirmation` for an unconfirmed critical
  change). `changeTime` is correctly destructive (it amends a critical alarm) and thus confirmation-
  gated. Comments at both surfaces now say this explicitly.
- **#8 — no authority.** `PreAlarmPromptContent`/`Button`/`Action` are pure values carrying only an
  identifier, localization keys, and flags — no alarm id, command, adapter, or closure; the model does
  not import `UserNotifications` or AlarmKit (lint's `domain_no_apple_frameworks` enforces it for
  `AlarmApplication`). Building the content mutates nothing; `keep` is a no-op label.
- **Review (ux-accessibility-reviewer + alarm-safety-reviewer, read-only). No BLOCKER** — ux confirmed
  the safe-to-destructive ordering, non-stigmatizing pressure-free copy, and genuine action-title
  localization-readiness; alarm-safety verified #7 honesty + always-present warning, the #6 flag
  derivation (destructive-only, never dropped, backed by the real `AlarmCommandProcessor` gate), #8
  no-authority, and keep-always-present. Applied: renamed the shim to `developmentFallback` (footgun),
  shortened "Remind me later" → "Remind later" (truncation + spec) and dropped the overpromising
  "here" from the warning, tightened the `authenticationRequired`-is-a-lock-gate comments, and added
  the informational-prompt warning test.
- **Handoffs (recorded).** (1) The runtime that builds the notification **body** (title/warning) MUST
  resolve those keys via `NSLocalizedString` (like the factory does for actions), not the dev-fallback
  shim. (2) The response handler (WG-084/085) MUST submit a destructive choice as an `AlarmCommand`
  through `AlarmCommandProcessor` with `userConfirmed` for a critical alarm — never a direct adapter
  call; since a critical `turnOffToday` is **not** `.foreground`, that handler must **foreground to
  collect real confirmation** and never treat "device unlocked" as "confirmed" (else the user taps and
  nothing happens — a #7-honesty risk at handling time). (3) A design note for the runtime/design
  owner: `changeTime` currently renders `.destructive` (red) like the true turn-off; consider reserving
  red for `turnOffToday` alone. (4) The `UNNotificationCategory` option mapping + action-title
  truncation on narrow banners are on the WG-083 real-device checklist.

### WG-084 (2026-08-09): Keep-original pre-alarm action

- **What it is.** The response to the "Keep alarm" button (WG-083) — a new
  `AlarmCommand.keepOriginal(AlarmID)` handled by `applyKeepOriginal` (in a new
  `AlarmCommandProcessor+PreAlarm.swift` extension). It is **audit-only**: it appends a `.noOp`
  acknowledgement and returns `.noOp`.
- **No schedule mutation (#7, acceptance — HOLDS by construction).** The handler calls **only**
  `appendAudit`; it never touches `alarms.save`/`deleteAlarm`, `alarmManager.schedule`/`cancel`/
  `stopRing`, the outbox, or a revision — and it never even reads the alarm. The only adapter-invoking
  path (`runExternal`) is unreachable from it, so keep leaves both the local record and the system
  authority exactly as scheduled. Tested: the reloaded alarm is byte-identical and no adapter call is
  made.
- **Stale-safe by construction (acceptance).** Because it never reads or touches the alarm, a missing
  / deleted / already-rung alarm is the *same* inert no-op — no crash, no error surfaced, no adapter
  call (tested for the never-existed and post-delete cases). Not reading is strictly safer than
  reading (a read could throw and tempt an error path).
- **Audit acknowledgement (acceptance).** The ack is recorded with `outcome: .noOp`, `old`/`new` nil,
  and a no-PII reason — consistent with the codebase's existing non-mutation audits (the
  snooze/reconcile `.noOp` rows). "Audit *may* record the acknowledgement" is satisfied.
- **Never gated — the safe default.** `.keepOriginal` is classified **non-destructive** in
  `isDestructive`, so `authorize` returns `.authorized` at its short-circuit *without reading the
  alarm* — even for a critical alarm, even `userConfirmed: false`, **from any source**. Keep is the #7
  safe default that must never require confirmation; and since it mutates nothing, even an
  `.agentProposal`-sourced keep can only no-op (#4/#8, tested).
- **Structure.** Pre-alarm response handlers live in their own extension file (WG-085 turn-off-today
  and WG-087 remind-later will join it); `CommandContext` + `appendAudit` were widened `private` →
  internal so the extension can share them. Both remain **actor-isolated** on the `AlarmCommand-
  Processor` actor, so the single command boundary (#2) and authorize-every-command (#3) are intact —
  `process(...)` is still the only entry, and no external caller can forge an audit or bypass
  authorization.
- **Review (alarm-safety-reviewer, read-only). No BLOCKER / SHOULD-FIX** — the no-mutation,
  authorization, stale-safety, audit, and boundary-intact properties were all verified, and the two
  enum switches (`alarmID`, `isDestructive`) are compiler-enforced exhaustive. Applied its one
  actionable NIT: a test that an `.agentProposal`-sourced keep is still a no-op. Noted, not acted
  (out of scope): a future `Outcome.acknowledged` to make keep visually distinct in history (today it
  renders "No change needed"), and the pre-existing `default:` in `apply` (a future *new* command
  would fall into the safe-`.noOp` default rather than a compile error — the mutation guarantee rests
  on `authorize` + that safe default, not `apply` exhaustiveness).
- **Handoff.** The notification-response router maps `prealarm.action.keep` → `.keepOriginal(alarmID)`
  from `.notificationAction` by `.user`; WG-085/087 add their handlers to the same extension.

### WG-085 (2026-08-09): Turn-off-today action (occurrence-level cancel)

- **What it is.** Implements `.cancelOccurrence(AlarmID, fireTime:)` (previously `.unsupported`): turn off
  *today's* occurrence while keeping the alarm enabled, so the next recurrence still rings.
- **Modeling decision — a skip set on the domain `Alarm`.** Added `skippedOccurrences: Set<Date>` to
  `Alarm`; the scheduling engine's `nextOccurrence(for:)` advances past any skipped instant. Chosen
  over an occurrence-exceptions side table because it keeps the scheduling primitive pure and total
  (one input → one occurrence) and lets the **reconciler and policy engine see the same truth for
  free** (both already call `nextOccurrence(for:)`), so reconciliation can never resurrect a
  turned-off occurrence (pinned by `testReconciliationHonorsSkippedOccurrence`). Backward-compatible:
  the alarm persists as a JSON payload (no Core Data migration), and `init(from:)` decodes a missing
  key to `[]` (`decodeIfPresent ?? []`).
- **Only the occurrence is affected (acceptance).** `applyCancelOccurrence` builds the mutated alarm
  from the **stored** record, changing only `skippedOccurrences` (+ `revision`/`updatedAt`) — never
  `isEnabled`, `schedule`, `criticality`, or policies. The command carries **no `Alarm` payload**, so
  (unlike `.update(alarm)`) a caller cannot smuggle a broader change through it.
- **Critical alarm requires confirmation (#6, acceptance).** `.cancelOccurrence` is destructive, so
  `authorize` returns `.needsConfirmation` for a critical (or imminent) alarm unless `userConfirmed` —
  and the gate runs *before* `apply`, so an unconfirmed critical turn-off mutates nothing (no skip, no
  reschedule, no adapter call). An `.agentProposal` turn-off of a critical alarm is hard-rejected (#4).
- **Next recurrence remains correct (acceptance).** `applyMutation` reschedules AlarmKit to the
  skip-aware next occurrence (schedule replaces by alarm id → today is superseded, tomorrow rings). A
  **one-time** alarm's only occurrence, skipped, yields no next occurrence → AlarmKit is cancelled
  (the occurrence *is* the alarm). Stale-safe: a past `fireTime` or missing alarm is a `.noOp`.
- **Robust skip match (fail-safe).** The engine matches by **whole second** (occurrences are
  second-aligned), so the skip survives `Date`'s JSON float round-trip and can't trap on a non-finite
  persisted value — not fragile exact-`Double` equality. Every uncertain edge fails **toward ringing**:
  a follow-local zone change remaps the instant → it no longer matches → the alarm still rings; a
  failed / uncertain reschedule leaves the local skip durable (#10) for reconciliation to re-arm (a
  spurious today ring, never a missed one) — pinned by `testTurnOffTodayPersistsSkipEvenIfReschedule-
  Fails`.
- **Restructuring.** To hold the 400-line processor file, the pure `outboxKey` moved to `+Reasons`
  (a `static`, byte-identical key format → outbox idempotency unchanged) and several comments were
  trimmed (no behavioral change; `applyMutation`/`alarmManager`/`clock`/`alarms` stay `private` — the
  #2/#3 boundary is intact).
- **Review (alarm-safety-reviewer + ios-architect, read-only). No BLOCKER** — all three acceptance
  criteria hold and every uncertain edge fails safe; ios-architect confirmed backward-compat, engine
  termination (`0...count` is correct, not off-by-one), the pure `outboxKey` move, and domain layering.
  Applied: the **whole-second engine match** (was fragile exact-`Double` equality; ios-architect SF1),
  and three tests — reconciler-honors-skip, skip-durable-on-failed-reschedule, and idempotent-double-
  turn-off. **Deferred (NIT):** skip-set pruning is lazy (only on the next turn-off) — bounded and
  harmless (a past skip never matches a future candidate). **Handoffs:** the notification-response
  router maps `prealarm.action.turnOffToday` → `.cancelOccurrence(id, fireTime:)` with the **exact
  engine-produced** next occurrence (a re-derived instant that drifts would silently miss the skip and
  ring) from `.notificationAction`, foregrounding a critical turn-off for #6 confirmation (WG-083);
  before WG-086, relocate the occurrence handlers into an `AlarmCommandProcessor+Occurrence.swift`
  extension (`applyMutation`/`appendAudit` are already internal) rather than trimming further.

### WG-087 (2026-08-09): Remind-later action

- **What it is.** `PreAlarmReminder` (pure, Foundation-only, `AlarmApplication`) is the calculator
  behind a pre-alarm prompt's "Remind me later" button: `next(now:alarmFireTime:remindersUsed:critical-
  ity:config:)` returns a bounded re-prompt `Date` or `.exhausted(.reachedCap / .noSafeWindow)`. It
  defers the **prompt**, never the alarm.
- **Reminder cannot extend beyond safe bounds (acceptance).** A reminder is offered only when a full
  deferral fits with at least `minLeadBeforeAlarm` to spare before the alarm (`now + interval <=
  alarmFireTime - minLead`); otherwise `.noSafeWindow`. The `Config` initializer **clamps every value
  to a safe range** (interval [60, 1800] s, minLead [30, 600] s), so no config — including a 0/negative
  interval or a negative minLead — can produce a near-instant or past-the-alarm re-prompt. A reminder
  therefore always lands ≥ 30 s before the ring, never at or after it.
- **Critical alarms retain original schedule (acceptance).** Structural: `next(...)` takes
  `alarmFireTime` **by value** and returns a prompt time — there is no `Alarm`, `AlarmCommand`,
  adapter, or persistence anywhere, so remind-later cannot change the schedule. Criticality only
  **tightens**: the critical cap is clamped ≤ the standard cap (critical: 1, standard: 3 by default),
  so a critical alarm is deferred at most once and always rings exactly when scheduled.
- **Repeated prompts are capped (acceptance).** `remindersUsed >= maxReminders(for:)` → `.reachedCap`
  (standard ≤ 5, critical ≤ standard, both ≥ 0). A **negative** `remindersUsed` fails closed (never
  resets the counter to grant extras). The `.remind(at:remindersUsed:)` case returns the incremented
  count for the caller to persist. Fail-closed on a non-finite `now`/`alarmFireTime` (Date comparison
  is NaN-blind) → `.noSafeWindow`; and an exhausted reminder is #7-safe (no prompt reappears, the
  alarm rings as scheduled — the user is no worse off than ignoring the prompt).
- **Review (alarm-safety-reviewer, read-only). No BLOCKER / SHOULD-FIX** — the three acceptance
  criteria hold under adversarial input (no reminder can land at/after the alarm; the alarm is
  untouched by type; the cap can't be bypassed via config). Applied its one NIT: the negative
  `remindersUsed` fail-closed guard (+ test). Left as-is (NIT, both outcomes `.exhausted`/safe): the
  cap check precedes the finiteness check, so a non-finite clock with an already-reached cap reports
  `.reachedCap` — the more honest reason for that corner anyway.
- **Handoff (the load-bearing runtime obligation).** WG-087 is the pure calculator; the notification-
  response handler that reschedules the prompt is the pre-alarm runtime's (joins the
  `AlarmCommandProcessor` pre-alarm extension). That runtime **must persist the incremented
  `remindersUsed`** across the notification round-trip, app termination/relaunch, and stale/duplicate
  notification actions — otherwise the cap is bypassable at runtime even though this calculator is
  correct. That persistence is where the "repeated prompts are capped" invariant is truly enforced and
  must be tested.

### WG-088 (2026-08-09): Pre-alarm background opportunity handler

- **What it is.** `PreAlarmBackgroundRunner` (pure, Foundation-only, `AlarmApplication`) runs one
  pre-alarm background opportunity, plus `BackgroundTaskHandle` — a minimal protocol wrapping the
  app-facing subset of `BGTask` (`setExpirationHandler` + `complete`) so the logic is testable without
  `BackgroundTasks`.
- **Failure produces no alarm change (acceptance + the safety property).** The runner holds **no alarm
  authority** — no repository, adapter, command processor, or persistence; it only invokes the injected
  advisory `work` and `scheduleNext`, and discards the work's result. So a failed / cancelled / expired
  run structurally cannot change an alarm. This satisfies "**never require a `BGTaskScheduler` run to
  preserve a critical alarm**" (#9/#10): the schedule lives in AlarmKit + reconciliation, a graph this
  runner is entirely absent from.
- **Opportunistic + expiration-safe (acceptance).** `run` (1) **reschedules the next opportunity
  first** (so a crash/expiry mid-run still leaves one queued), (2) runs `work` in a **cancellable**
  task and wires expiration → cancel **race-free** (an expiration that fires before the work task is
  stored still cancels it — via a `Mutex` that records the intent), (3) **completes** the task
  (unsuccessful if cancelled). `work` **must be cooperatively cancellable**; an uncooperative one is
  force-terminated by the OS — safe (no alarm seam, next opportunity already queued), just wasteful
  (documented, not silently promised).
- **Reschedules responsibly without tight loops (acceptance).** `nextRequestTime = now +
  minimumReschedule`, clamped **≥ 60 s** (non-finite → 900 s), rescheduled exactly once, first — no
  config yields a sub-minute/zero/negative delay, so submissions can't tight-loop.
- **Review (ios-architect, read-only). No BLOCKER — "ship-ready"; the safety property is airtight.**
  Applied both SHOULD-FIX: the **race-free expiration registration** (was a window where an early OS
  expiration left the work uncancelled → force-kill; + an instant-expiration test), and the
  **cooperative-cancellability documentation** (the docstring no longer over-promises "always
  completes"). Applied the NITs: the protocol notes `complete` must be idempotent at the adapter, and
  `now` must come from the injected `WallClock`.
- **Handoffs.** The real `BGTaskScheduler` adapter (conform a `BGTask` to `BackgroundTaskHandle`), the
  `BGTaskSchedulerPermittedIdentifiers` / Info.plist entries, and task registration are a **composition
  follow-on** (`AlarmInfrastructure` / `AppComposition`), mirroring the notification-adapter pattern.
  The composition builds `work` as the query → evidence → `PreAlarmEvaluator` → schedule-prompt
  pipeline — which **must route through the WG-083 prompt cooldown** (the evaluator is stateless) and
  **must be cooperatively cancellable**. WG-089 (foreground fallback) owns cancelling an in-flight BG
  evaluation on foreground + prompt de-duplication.

### WG-086 (2026-08-09): Change-time action

- **What it is.** `ChangeTimeProposal` (pure, Foundation-only, `AlarmApplication`) — the value the
  "Change time" pre-alarm action opens for the user to review before saving. Tapping change-time does
  **not** mutate; the router returns `.presentChangeTimeUI`, never a command.
- **Opens a proposal, not immediate mutation (acceptance, HOLDS).** The proposal is **inert**:
  constructing it, `proposedAlarm(now:)`, `command(now:)`, `previewNextOccurrence`, and `isChange`
  mutate nothing (no persistence, no AlarmKit, not even a read). Its **only** mutating exit is
  `command(now:)` → a plain `.update(Alarm)` submitted through `AlarmCommandProcessor`, which
  authorizes it. It holds no adapter/processor/persistence — it merely *carries* a would-be command,
  mirroring `AlarmProposal`.
- **Original remains active until save succeeds (acceptance, HOLDS).** The live stored alarm is
  untouched until an `.update` actually applies; a failed/uncertain save preserves the original desired
  state for reconciliation (#10). `proposedAlarm` changes only the wall-clock time (+ a one-time date)
  — preserving `id` (so it updates, never duplicates), enabled, the **anchor IANA zone** (no silent
  re-anchor, #11/#16), `criticality` (#31), every policy, and `skippedOccurrences` — bumps `revision`,
  and sets `updatedAt = max(now, createdAt)` (respecting the `updatedAt >= createdAt` invariant).
- **Race with imminent ring handled (acceptance, HOLDS).** Opening/holding a proposal never suppresses
  an imminent ring (it's inert). On save, a **critical** (or imminent-critical) retime returns
  `.needsConfirmation`, mutating nothing (#6); a **standard** retime applies and **reschedules
  in-place** (`schedule` replaces by alarm id — no cancelled-but-not-yet-rescheduled gap where a ring
  could be lost). A standard imminent retime is authorized without confirmation, consistent with
  WG-028 (only a *critical* `.update` is gated) — a deliberate, in-scope-preserving posture.
- **Crash-safe.** `proposedAlarm` returns `nil` (not a force-unwrap) if the Alarm invariant rejects the
  copy; `command`/`previewNextOccurrence` propagate `nil`. A past one-time retime → `nil` (not
  saveable). No trap path.
- **Review (alarm-safety-reviewer, read-only). No BLOCKER / SHOULD-FIX** — all five properties verified
  (inert, original-active-until-save with correct field preservation, imminent race can't lose a
  critical alarm, crash-safe, no authority). Noted (not fixed — not WG-086 regressions): `revision + 1`
  is an unguarded add (codebase-wide pattern, unreachable in practice at `Int.max`); a one-time retime
  onto a DST spring-forward gap previews a shifted instant (engine WG-022, fails safe — still rings).
- **Handoff.** The change-time **editor UI** (a picker pre-filled from the proposal) + wiring the
  router's `.presentChangeTimeUI` → present it → on confirm submit `proposal.command(now:)` through
  `AlarmCommandProcessor` (foregrounding on `.needsConfirmation`) is the remaining app-shell composition
  step (implemented behind this pure proposal).

### WG-090 (2026-08-09): False-positive feedback loop

- **What it is.** `PreAlarmFeedback` (`AlarmDomain`, Foundation-only): `PreAlarmFeedbackCategory`
  (`notAwake` / `helpful`), an aggregate `PreAlarmFeedbackCounts` (two non-negative counters), and the
  `PreAlarmFeedbackStore` port (`record` / `counts`); plus a persisted `CoreDataPreAlarmFeedbackStore`
  (a v6 single-row `PreAlarmFeedbackRecord`). After a pre-alarm prompt the user can indicate the nudge
  was a false positive or helpful.
- **Local + coarse (acceptance, #41 — HOLDS strongly).** The entity has exactly three attributes:
  `singletonKey` + `notAwakeCount` + `helpfulCount`. `record` writes **only** the two clamped counts —
  no alarm id, no occurrence / fire time, no sleep-revealing timestamp, no raw motion/health/location/
  journal sample. The tally is genuinely aggregate (a single prompt's feedback folds into a `+1` and is
  unrecoverable). A **recursive** no-PII structural test pins the exact key set against a forbidden
  list (the WG-075 pattern). On-device Core Data only — no network/log/export path touches it.
- **Cannot silently retune critical behavior (acceptance, #8/#31 — HOLDS structurally).**
  `PreAlarmFeedback*` references no `Alarm`, `AlarmID`, `Criticality`, `AlarmCommand`, `ScheduleRule`,
  `AwakeEvidenceModel.Config`, adapter, or scheduling — so recording feedback has **no path** to
  whether/when a critical alarm rings, its gates, or an automatic model retune. Nothing outside the
  WG-090 files reads the tally (verified), so there is no auto-apply to WG-080 or scheduling. Pinned by
  a reflection test (the value is exactly two `Int`s, no alarm-authority child) and an integration test
  (recording every category over a shared store leaves a saved critical alarm byte-for-byte unchanged).
  Any advisory use of the tally to tune WG-080 must be a separate, explicit, user-initiated step.
- **Fail-closed + robustness.** `record` is best-effort non-throwing (a conflict rolls back, a genuine
  fault is swallowed — the alarm is never affected); `counts` returns `.empty` on an unreadable store;
  counts clamp negatives at zero on init + decode and **saturate** at `Int.max` (no overflow trap); the
  category is String-raw fail-closed (#27). No force-unwrap, no trap path.
- **Schema v6.** `PreAlarmFeedbackRecord` is a **purely additive** entity (no change to v1–v5) — the
  same inferred-lightweight-migration class as v2–v5; existing stores open safely.
- **Review (privacy-security-reviewer, read-only). No BLOCKER / SHOULD-FIX — "a model of data
  minimization"; all five properties hold and are pinned by strong tests.** No code change needed. It
  noted (process) that the store is not yet wired — which is *why* the no-auto-retune boundary is
  currently airtight — and (pre-existing, **not** WG-090) the verbatim-`label` audit-retention gap
  already tracked for WG-027, and the absent privacy manifest (release-time).
- **Handoff.** The prompt's **feedback affordance** (a UI control that calls `record(.notAwake)` /
  `record(.helpful)`) + constructing `CoreDataPreAlarmFeedbackStore` in `AppEnvironment` is the app-shell
  step. A **tripwire test** — asserting no background/pipeline type imports `PreAlarmFeedbackCounts` —
  should guard the "advisory, explicit-user-action-only, no auto-retune" boundary when the store is
  wired.

### Pre-alarm runtime composition (2026-08-09): tying the E05 primitives together

- **Why.** WG-080–089 each delivered a tested primitive and deferred its runtime glue as a handoff. This
  pass builds the **testable orchestration** that connects them, discharging those handoffs, so the
  remaining gap is only the thin device-framework adapters.
- **`PreAlarmResponseRouter` (`AlarmApplication`).** Pure, deterministic (`now` injected): maps a
  tapped WG-083 prompt-action identifier + context (alarm id, occurrence, criticality, remindersUsed)
  → a `PreAlarmResponse`. keep → `.submit(.keepOriginal)` (WG-084); turn-off-today →
  `.submit(.cancelOccurrence(fireTime:))` (WG-085); remind-later → `PreAlarmReminder` → `.reschedule-
  Prompt(at:)` / `.stopReminding` (WG-087); change-time → `.presentChangeTimeUI` (WG-086); unknown →
  `.ignored`. It **holds no authority** — a `.submit` is handed to `AlarmCommandProcessor`, which
  authorizes it and gates a critical/imminent change on confirmation (#6); the router never pre-sets
  `userConfirmed`, so the runtime foregrounds on `.needsConfirmation`. A `.reschedulePrompt` re-arms
  the prompt, never the alarm (#7/#8).
- **`PreAlarmPipeline` (`AlarmApplication`).** The advisory `work` a background opportunity (WG-088) or
  a foreground launch (WG-089) runs: recent-movement query (WG-081) → awake evidence + prompt policy
  (WG-080/082) → prompt de-dup (WG-089) → prompt content (WG-083). Returns the content to present, or
  `nil`. Holds no alarm authority — decides only *whether* to prompt and *what it says*.
- **`AppEnvironment`.** Now constructs the persisted `CoreDataPreAlarmPromptLedger` + `PreAlarmPrompt-
  Coordinator` so the background + foreground paths share one de-dup.
- **What remains device-wired (the honest gap to "runs on a phone").** The thin, device-verified
  adapters: (1) a `UNUserNotificationCenterDelegate` that reads a tapped action's `userInfo` → the
  router → `AlarmCommandProcessor` (foregrounding on `.needsConfirmation`); (2) notification scheduling
  that presents the pipeline's content via the WG-083 `UNNotificationCategory`; (3) the `BGTaskScheduler`
  registration that runs the pipeline as `PreAlarmBackgroundRunner`'s `work`, + the foreground entry
  point; (4) the persisted remind-later count. And separately, swapping the interim
  `DeferredAlarmManagerAdapter` for the real `SystemAlarmManagerAdapter` (so alarms ring) still needs
  the AlarmKit authorization **UI shell** (WG-025 built the flow logic; the app-shell UI + Info.plist
  usage descriptions are the remaining piece). Review: none run — this is thin composition of
  already-adversarially-reviewed primitives with no new authority; the router's one safety-relevant
  mapping (turn-off → `cancelOccurrence`, not pre-confirmed) is directly tested and the processor's #6
  gate is intact.

### Runs-on-a-phone (2026-08-10): device-integration plan + AlarmKit/Motion usage descriptions

- **Context.** Every *component* needed to ring on a device already exists and is adversarially
  reviewed: the real `SystemAlarmManagerAdapter` (AlarmKit, #1), the `AlarmAuthorizationCoordinator`
  (WG-025), `PreAlarmNotificationCategoryFactory` (UserNotifications), `PreAlarmBackgroundRunner`
  (BGTaskScheduler), the `PreAlarmResponseRouter`, and the full SwiftUI shell. What's missing is
  **integration + device configuration**, not new logic. `AppEnvironment.make()` still composes the
  interim `DeferredAlarmManagerAdapter` (nothing rings; `schedulesAlarmsInSystem = false`, honestly
  disclosed in the list UI); `AlarmAuthorizationCoordinator` is constructed nowhere; no launch
  reconciliation runs; and there were **no Info.plist usage descriptions**.
- **Decision (this step).** Add `NSAlarmKitUsageDescription` + `NSMotionUsageDescription` as
  `INFOPLIST_KEY_*` build settings (`GENERATE_INFOPLIST_FILE` is on; there is no checked-in plist).
  These are a hard prerequisite — the app **crashes / is App-Review-rejected the instant it touches
  AlarmKit or Core Motion** without them. Only these two: the shipped features (E02 alarms, E04/E05
  motion) touch only these frameworks; Health/Location/Calendar strings land with E06–E08 (YAGNI). The
  copy names the specific use and disclaims location + saved workouts/health records (#41). No runtime
  behavior changes yet — `make ci-fast` stays green (616 tests; tests/previews use the fake/in-memory
  graph and never touch these frameworks).
- **The ordered, non-regressing plan.** Each step is safe on its own and never claims a safety it can't
  deliver:
  1. ✅ **Usage descriptions** (this step).
  2. **Permission UI**: an accessible explanation screen + a concrete `SettingsOpener`
     (`UIApplication.openSettingsURLString`) driving `AlarmAuthorizationCoordinator`
     (`explainThenRequest` → `requestAfterExplanation`) — the system dialog must never appear
     unexplained (WG-025 acceptance).
  3. **Flip to the real adapter**: `production()` → `SystemAlarmManagerAdapter` +
     `schedulesAlarmsInSystem = true`, while `inMemory()` keeps the fake so **ci-fast + SwiftUI
     previews never touch `AlarmManager.shared`**. **Ordering invariant:** this MUST follow step 2 —
     flipping first makes every create fail `.notAuthorized` (fail-closed guard in `scheduleFixed`) and
     would make the UI falsely imply ringing (a #7 disclosure regression). Never set
     `schedulesAlarmsInSystem = true` before the prompt is wired.
  4. **Launch reconciliation** (WG-029) at app start — re-arm persisted alarms against the authority on
     relaunch; opportunistic, never required for a critical alarm (#9).
  5. **Notification delegate**: register the categories, schedule the pre-alarm notification, and route
     tapped actions through `PreAlarmResponseRouter` (turn-off → `cancelOccurrence`; a critical change
     stays #6-gated by the processor).
  6. **BGTaskScheduler registration** → `PreAlarmBackgroundRunner` (opportunistic; #9).
  7. **Feedback affordance** (WG-090 `record`) + change-time editor entry (WG-086).
- **What ci can and can't verify.** Steps 3–6 exercise `AlarmManager.shared` /
  `UNUserNotificationCenter` / `BGTaskScheduler`, which need a real device — they are **not** unit-
  testable, so each carries a `RELEASE_CHECKLIST.md` device item. The deterministic core (adapters
  behind ports, auth logic, routing, evidence) stays fully covered by `make ci-fast`.

### Runs-on-a-phone steps 2–3 (2026-08-10): real AlarmKit adapter + authorization UI

- **What.** `production()` now composes the real `SystemAlarmManagerAdapter` (so alarms ring) + a
  `UIKitSettingsOpener` + `schedulesAlarmsInSystem: true`, bundled through a `SystemWiring` value;
  `inMemory()` keeps the interim `DeferredAlarmManagerAdapter` + a `NoopSettingsOpener` so **ci-fast and
  SwiftUI previews never touch `AlarmManager.shared`**. The `AlarmAuthorizationCoordinator` (WG-025) is
  built over the **same** adapter the processor schedules through (auth and scheduling can never
  disagree) and surfaced by a new alarm-list `AlarmPermissionBanner` + explanation sheet.
- **Honest disclosure (#7).** The static "won't ring here" banner is replaced by an authorization-aware
  one: authorized → no banner (it rings); notDetermined → "Turn on alarms…" → explanation → system
  prompt; denied → "…needs permission" + Open Settings; restricted → informational; unknown → keep-safe
  retry. The explanation always precedes the system dialog (WG-025). The permission path is read-only
  with respect to alarms — a denial/interruption never drops one (#10).
- **Not-authorized is a deferral, not a failure (review fix).** With the real adapter, a create *before*
  permission would persist locally (source of truth) but `scheduleFixed` throws `.notAuthorized`, which
  previously surfaced as "Couldn't save alarm" — dishonest (it WAS saved) and duplicate-prone on retry.
  Now `callExternal` maps `AlarmManagerError.notAuthorized` → `.uncertain` (reconcile-later, folded into
  the existing uncertain/cancelled catch), so create reports **`.created`/"saved"**, the banner drives
  the grant, and reconciliation places it once authorized. In production only *scheduling* can be
  not-authorized (the real `cancel`/`stopRing` never throw it); #10 holds — the local alarm is always
  preserved. Pinned by `testScheduleNotAuthorizedIsDeferredAndPreservesLocalAlarm` +
  `testCancelNotAuthorizedIsDeferredAndLeavesLocalDisabled`.
- **Reviews.** `alarm-safety-reviewer` (read-only): hermeticity, no-alarm-drop, and same-adapter
  consistency all **pass**; it caught the not-authorized-create honesty gap (fixed above). NIT:
  AlarmKit has no `.restricted` state (the domain's `.restricted` / the restricted banner branch are
  defensive-only; `@unknown default` fails closed to `.denied`) — documented at the map site.
  `ux-accessibility-reviewer` (read-only): applied — the banner message is a combined labeled element
  while the button stays independently actionable, each action carries a consequence hint, and the
  footnote font override (which shrank the tap target + undercut filled-label contrast) is dropped for
  `.controlSize(.small)`. The explanation body's line-wrapped string concatenation is consistent with
  existing app copy and is deferred to **E11** (localization) with the rest of the strings.
- **Device-only.** Alarms actually ringing + the real system prompt need a device (not unit-testable);
  each has a `RELEASE_CHECKLIST.md` item. `make ci-fast` green — 624 tests.
- **Handoff.** Steps 4–7: launch reconciliation (WG-029), notification delegate →
  `PreAlarmResponseRouter`, `BGTaskScheduler` → `PreAlarmBackgroundRunner`, feedback/edit UI.

### Runs-on-a-phone step 4 (2026-08-10): launch/foreground reconciliation wired

- **What.** The WG-029 reconciler existed but nothing triggered it. Added `reconcile()` to the
  `AlarmCommandProcessing` protocol (the concrete actor already implemented it) and a
  `AlarmListViewModel.reconcile()` that shows the non-blocking reconciling banner, runs
  `processor.reconcile()`, then reloads. The alarm list calls it **on launch (`.task`) and every
  foreground** (`scenePhase == .active`), replacing the bare `load()`.
- **Why it's safe to run every foreground.** `reconcile()` is idempotent and **fails safe** (#10): an
  unreadable ground-truth or desired state repairs nothing (`skipped`); each repair's uncertain/failed
  outcome preserves the local alarm; and cancels are future-only, so a **currently ringing** alarm is
  never cancelled (#24). It is **opportunistic** — never required for a critical alarm to ring (#9). A
  read-only context (no processor: previews/tests) just reloads. With the real adapter now composed
  (step 3), this is what re-arms saved alarms after relaunch and corrects drift.
- **Tests.** `make ci-fast` green — 626. `AlarmListViewModelTests`: reconcile runs through the
  processor then reloads + clears the banner; and a no-processor context still reloads safely. The
  repair correctness itself is already covered by the WG-029 reconciler suite. Device verification
  (real AlarmKit read-back incl. criticality) → `RELEASE_CHECKLIST.md`.

### Runs-on-a-phone step 5 (2026-08-10): pre-alarm notification response runtime

- **What.** When a user taps an action on a pre-alarm prompt notification, the app decodes the
  notification's `userInfo` → routes it (the tested `PreAlarmResponseRouter`) → executes it. New:
  `PreAlarmNotificationPayload` (userInfo ↔ context, **fail-closed** decode), a
  `PreAlarmNotificationScheduling` port (register / post / cancel — UserNotifications wrapped),
  `PreAlarmResponseEffect` + `PreAlarmNotificationResponder` (the routing+execution), the real
  `SystemPreAlarmNotificationScheduler` (calendar-triggered, whole-second id), a
  `NoopPreAlarmNotificationScheduler` (test/preview), the `UNUserNotificationCenterDelegate`, and launch
  registration in `RootView` (gated on `schedulesAlarmsInSystem` so ci/previews never touch the
  framework).
- **Safety (alarm-safety review: SOUND, no blocker).** A **critical** turn-off tapped from a
  notification cannot mutate the alarm: the responder submits through `AlarmCommandProcessor` with
  **`userConfirmed: false`**, so the policy engine returns `.needsConfirmation` and nothing is
  persisted/scheduled (#6) — verified end-to-end. The `userInfo` decode is strictly fail-closed (every
  field validated; any miss → ignored), so a corrupt/foreign notification never mis-routes to the wrong
  alarm/occurrence (#7). The category is registered with the **union** of actions (iOS categories are
  static) — safe because the processor re-authorizes every routed command against the current alarm's
  policy, so a shown-but-forbidden action can't bypass authorization (MVP simplification; the in-app
  prompt still shows the exact policy subset). remind-later only re-posts the advisory prompt (never the
  alarm, #7/#8). The prompt is a UserNotifications-only surface; the real alarm is AlarmKit — a
  missed/failed/duplicate prompt can't suppress the ring.
- **Applied review fix.** A turn-off that took effect now **reaps any pending re-prompt** for that
  occurrence (`cancelPrompt`), so a remind-later scheduled earlier never re-prompts about an alarm
  already turned off.
- **Documented follow-ups (both prompt-only — no alarm-safety impact).** (1) *Persist `remindersUsed`
  in the ledger*: the reminder count currently self-propagates in the notification's `userInfo`, so a
  stale/duplicate notification tap could reset it and exceed the cap (an annoyance vector, never an
  alarm change). Gating `.reschedulePrompt` on the persisted `PreAlarmPromptCoordinator` belongs with
  **step 6's** posting infrastructure. (2) *Foreground the confirmation / change-time picker*: the
  responder returns `.needsConfirmation` / `.presentChangeTimeUI` but the delegate doesn't yet surface
  a screen — the alarm is never wrongly changed in the meantime (fail-safe #6/#7), but the user's intent
  isn't yet visibly acted on. Both are the UI/navigation follow-up.
- **Scope.** Step 5 = the response side + category registration. Step 6 = the BG task runs the pipeline
  and **posts** the initial prompt (+ notification authorization). `make ci-fast` green — 635 tests
  (payload round-trip/fail-closed + responder routing incl. the #6 critical-gate). Device-only: the
  real tap→route and the system prompt → `RELEASE_CHECKLIST.md`.

### Runs-on-a-phone step 6 (2026-08-10): pre-alarm evaluation work + foreground delivery

- **What.** `PreAlarmBackgroundWork` — the advisory `work` that finds each enabled alarm whose next
  occurrence is inside its pre-alarm lead window, runs the `PreAlarmPipeline` (movement → awake evidence
  → prompt policy → de-dup), and **posts** the advisory notification when a prompt is recommended.
  Composed in `AppEnvironment` (production: the real Core Motion pipeline; the in-memory graph: an
  `UnavailablePedometerSource`, so it never posts). `RootView` runs it on **launch and every foreground**
  (the WG-089 foreground fallback) and requests notification authorization, both gated on
  `schedulesAlarmsInSystem` so ci/previews never touch the frameworks.
- **Safety.** The work holds **no alarm authority** (#7/#8/#9): it only reads alarms + posts a
  notification. Fail-safe — an unreadable repository posts nothing; de-duped by the persisted
  coordinator (at most one prompt per occurrence); only inside the lead window; the pipeline applies the
  evidence + imminence gates. A failed/skipped pass changes no alarm, and a critical alarm rings
  regardless (#9). Cooperatively cancellable (checks `Task.isCancelled`) for a background expiry.
- **Foreground is the delivery; background is opportunistic.** Per the architecture rule — *"treat
  background execution as opportunistic; never require a `BGTaskScheduler` run to preserve a critical
  alarm"* (#9) — the **foreground path wired here is the reliable delivery** (a prompt appears when the
  app is open near an alarm). The opportunistic `BGTaskScheduler` trigger (running the same `work`
  through the already-built, tested `PreAlarmBackgroundRunner`, WG-088) is the **remaining device
  follow-up**: it needs the Info.plist `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes` and
  on-device verification, and is **never required** for correctness (the foreground path + the alarm
  itself deliver without it). Deferred deliberately rather than shipping unverifiable BG registration +
  a possibly-wrong Info.plist.
- **Carried-forward follow-up (from step 5).** The initial prompt posts `remindersUsed: 0`; persisting
  the reminder count in the ledger (so a stale/duplicate notification tap can't exceed the cap) rides
  with this posting infrastructure — still a prompt-only concern (no alarm-safety impact).
- **Tests.** `make ci-fast` green — 640. `PreAlarmBackgroundWorkTests` (6): posts once for an alarm in
  the lead window with recent movement; **de-dups** a second pass; posts nothing outside the window, for
  a disabled pre-alarm policy, or when the repo is unreadable (fail-safe #9). Device-only: the real
  foreground prompt + the notification-permission prompt → `RELEASE_CHECKLIST.md`.

### Runs-on-a-phone step 7 (2026-08-10): pre-alarm feedback affordance (WG-090 handoff)

- **What.** Composed `PreAlarmFeedbackStore` in `AppEnvironment` (`CoreDataPreAlarmFeedbackStore` over
  the shared persistence — on-disk in production, in-memory for tests/previews), a tested
  `PreAlarmFeedbackModel`, and an accessible `PreAlarmFeedbackSection` (two low-friction taps: "The
  pre-alarm was helpful" / "I wasn't actually awake"). Shown when **editing an alarm that has the
  pre-alarm check enabled**; on a tap it records the coarse category and thanks the user.
- **Safety / privacy.** Advisory only, discharging WG-090's app-shell handoff. The affordance writes to
  the **aggregate, on-device** two-counter tally (no id / timestamp / sample, #41); it holds **no alarm
  authority and cannot retune any behavior** (#8/#31) — the copy states it "never changes when your
  alarms ring." The store's no-alarm-authority + no-PII properties were already adversarially reviewed
  under WG-090; this step only adds the composition + the affordance.
- **Scope.** The **WG-090 feedback** affordance is done. The **WG-086 change-time-from-notification**
  presentation (surfacing the `.presentChangeTimeUI` / critical-confirmation effect the responder
  returns) remains the step-5 follow-up — it needs the delegate → app navigation and is advisory (the
  alarm is never wrongly changed meanwhile, #6/#7). The in-app change-time *proposal + editor* (WG-086)
  already exist and are reachable via the normal edit flow; only the notification-driven entry is
  deferred.
- **Tests.** `make ci-fast` green — 643. `PreAlarmFeedbackModelTests` (2): a tap records only the chosen
  category and marks the session; `AppEnvironmentTests`: feedback round-trips through the composed
  store. Device: the on-device affordance → `RELEASE_CHECKLIST.md`.
- **Runs-on-a-phone steps 2–7 complete** (with the documented, advisory-only follow-ups: the
  opportunistic `BGTaskScheduler` trigger, the change-time-from-notification UI, and persisting
  `remindersUsed` — none affect whether or when an alarm rings, #9).

### WG-022 (2026-08-10): Explicit DST policy for skipped and duplicated local times

- **Policy.** A **spring-forward** wall-clock time (a *gap* — it never happens) fires at the gap's
  **end** — the DST transition instant — so an alarm is **never silently skipped**. A **fall-back**
  wall-clock time (a *duplicate* — it happens twice) fires at the **first / earlier** instant, so a
  wake alarm rings at the soonest valid moment. This policy is now **explicit and identical for one-time
  and weekly** rules, and exposed as a **user-visible** `DSTResolution`
  (`exact`/`skippedToGapEnd`/`ambiguousUsedFirst`) via `resolvedNextOccurrence` (a UI can explain "2:30
  doesn't happen that night; your alarm rings at 3:00"; the copy itself is E11).
- **Mechanism.** Both rule kinds resolve a specific calendar day + wall-clock through one `resolveDay`.
  A gap is detected **on the intended day** (Foundation's `date(from:)` never skips but shifts a gap's
  wall-clock) and resolved to `timeZone.nextDaylightSavingTimeTransition` — robust for **any** DST delta,
  including **Lord Howe's 30-minute** shift. Ambiguity is classified via the transition's **offset drop**
  (a fall-back has `delta > 0`; the instant sits within `delta` of the transition), which likewise
  handles the 30-min case. A naive time-of-day roll is deliberately **not** used for gaps — with only
  02:00–02:29 missing it would jump to the next day/week (see the review BLOCKER below).
- **Convergence.** One-time previously diverged from weekly on a gap (NY 02:30 → 03:30 vs 03:00); both
  now resolve to the gap end (03:00).
- **Review (alarm-safety-reviewer, read-only).** Found a **[BLOCKER]**: the *weekly* path silently
  rolled a **sub-hour (30-min) gap to the next week** — a ~7-day skip of a wake alarm, reported as
  `.exact` (invisible), with no horizon clamp downstream to catch it. **Fixed**: `earliestWeekly` now
  iterates weekdays through `resolveDay`, so the gap policy applies uniformly; pinned by
  `testLordHoweWeeklySpringForwardFiresAtGapEndNotNextWeek`. A **[SHOULD-FIX]** — an International Date
  Line *whole-day* skip (e.g. `Pacific/Apia` 2011-12-30) currently mis-resolves as `.exact` — is out of
  WG-022 scope but marked `KNOWN-GAP WG-023` in `resolveDay` so it isn't mistaken for correct; **WG-023
  fixes it**. All other paths were verified sound (one-time gap→transition robust incl. a 2-hour
  `Antarctica/Troll` gap; classify edge cases; first/earlier on both paths; no `nextOccurrence`
  regressions — past→nil, exactly-now→nil, boundaries unchanged).
- **Tests.** `make ci-fast` green — 649. London / New York / Lord Howe spring + fall (one-time **and**
  weekly), plus convergence + `.exact`. Device: a manual DST-boundary check → `RELEASE_CHECKLIST.md`.

### WG-091 (2026-08-10): Adversarial test — bathroom-return-to-bed scenario

- **What it is.** A pure adversarial **scenario test** (`BathroomReturnToBedScenarioTests`, 10 cases)
  pinning the canonical false-positive trap for movement-based awake detection: the sleeper takes a few
  steps to the bathroom and returns to bed. **No production code** — the WG-080 model, WG-082
  evaluator, and the pipeline already handle it; the test locks the *contract* so a future change can't
  regress it silently.
- **What it pins.** (1) *Brief movement is conservative* — a few steps reach exactly `.weak` (one
  uncorroborated signal), and once movement is stale (back in bed) the evaluator declines with reason
  `.insufficientEvidence` (asserted **by reason**, so it can't pass for the wrong reason). (2) *No
  auto-cancel (#8)* — a substantial recent trip reads `.likely` (WG-080's **documented, tolerated
  residual**: the aggregate-history path carries no episode timeline, so it can't tell a bathroom trip
  from a real wake-up walk), but the recommendation carries no command/adapter/alarm-id — the strongest
  outcome is an advisory prompt whose safe default is `keep` (#7). (3) *Fail-closed sensing* — a source
  that reports steps **while unavailable** still declines as `.sourceUnavailable` (never
  `.insufficientEvidence`): couldn't-observe ≠ confirmed-still. (4) *Let it ring in the final stretch* —
  a `.likely` trip at the imminence cutoff (critical 120 s / standard 60 s, strict `>`) does **not**
  prompt. (5) *#6 into the button* — a critical turn-off carries the confirmation flag into the
  destructive button; `keep` never confirms. (6) *No trap* — a saturated (`Int.max`) step count still
  only prompts. (7) *Repeated trips* in one occurrence are de-duped by the per-(alarm, occurrence)
  ledger, **not** by evidence decay.
- **Why advisory-is-enough.** The residual false `.likely` is acceptable precisely because the whole
  path is advisory: suppression is *structurally* impossible (the recommendation holds no mutation
  authority), so the worst case is an unnecessary prompt the user dismisses — the alarm still rings.
- **Review.** `motion-red-team` (read-only) judged the initial 6-case draft *adequate but thin*: no
  variant produced an unsafe outcome (suppression is structurally impossible), but two axes could
  regress a *reason* undetected. Its **[BLOCKER]** (untested source-unavailable) + four **[SHOULD-FIX]**
  (assert exact `.weak` bucket, assert decline *reasons*, imminence-boundary case, saturation through
  the pipeline) + two **[NIT]** (thread #6 into the button; frame repeated-trip de-dup) were **all
  applied**, growing the suite 6 → 10. No production change — the exposure was purely test adequacy.
- **Handoff.** On-device UAT: a real bathroom trip in the pre-alarm window at most prompts (keep
  default) and never cancels; back in bed / sensor unavailable → no prompt → `RELEASE_CHECKLIST.md`.
- **Completes E05** (Pre-alarm smart wake): WG-080…WG-091 all Complete.

### WG-089 (2026-08-09): Foreground fallback — pre-alarm prompt de-dup ledger

- **What it is.** An **idempotency-key prompt-suppression ledger** so a pre-alarm prompt surfaces at
  most once per (alarm, occurrence), whether the trigger is the background opportunity (WG-088) or a
  foreground app launch: `PreAlarmPromptKey` (`AlarmDomain`), the `PreAlarmPromptLedger` port
  (`claim(_:at:) async -> Bool`), the persisted `CoreDataPreAlarmPromptLedger`, and the
  `PreAlarmPromptCoordinator` (`surface = shouldPrompt && ledger.claim`).
- **Original alarm remains clear (the safety property, HOLDS structurally).** The coordinator holds
  **only** the ledger and reads the WG-082 recommendation's `shouldPrompt`; the ledger touches only the
  `PreAlarmPromptRecord` entity. No `Alarm`, `AlarmCommand`, adapter, processor, or alarm persistence
  anywhere — so de-dup/suppression can never cancel, delay, or reschedule an alarm. The worst case of
  every path is a **missed advisory prompt**; the alarm rings exactly as scheduled (#7/#8). Turn-off /
  keep still route through `AlarmCommandProcessor`, untouched.
- **Prompt suppression uses idempotency keys (acceptance).** The key is `alarmID +` the occurrence
  **truncated to a whole second** (occurrences are second-aligned; kept as a `Double`, never `Int` —
  `.distantFuture` is finite but exceeds `Int64.max`, so an `Int` conversion would **trap**; the
  earlier draft crashed there, now fixed + regression-tested). Two different alarms at the same instant
  are different keys (no cross-alarm suppression, tested); a declined recommendation does **not** claim
  the key, so a later genuine prompt still surfaces.
- **Without duplicate prompting, across relaunch (acceptance).** The ledger is **persisted** (a v5 Core
  Data entity, `idempotencyKey` unique), so a foreground fallback after a background prompt — even
  across app termination — de-dups (tested via a fresh ledger over the same store). The `claim` is
  **atomic**: fetch-first + insert, with the uniqueness constraint + `NSMergePolicy.error` as the real
  guarantor — a concurrent loser's `save` throws a conflict, caught (rollback → `false`, the expected
  non-error outcome, mirroring the outbox); exactly one concurrent claim wins (tested).
- **Fail-closed degradation (documented).** A **genuine** storage fault (distinct from that conflict)
  also returns `false` — suppress rather than risk a duplicate. So a persistently wedged store (disk
  full, file-protection-locked before first unlock, corruption) silently disables **all** pre-alarm
  prompts. This is **safe** (the alarm is unaffected — the #7 baseline) and is the better of the two
  safe directions for "without duplicate prompting"; recorded per the WG-016 fail-closed precedent.
  Claims older than 48 h are pruned on each claim (bounded; a past occurrence's key never matches a
  future one, so pruning can't cause a duplicate).
- **Schema v5 migration.** `PreAlarmPromptRecord` is a **purely additive** entity (no change to v1–v4
  entities, no relationship to `AlarmRecord`) — the same inferred-lightweight-migration pattern the app
  already used for v2/v3/v4 under `shouldInferMappingModelAutomatically`; no mapping model is needed and
  existing user stores are safe. A dedicated v4→v5 **on-disk** migration fixture belongs to the WG-017
  migration harness (still unbuilt) — the follow-on that would add coverage.
- **Review (ios-architect + alarm-safety-reviewer, read-only).** Both confirmed the safety property,
  the atomic-claim correctness (faithful outbox mirror), pruning, key identity, layering, and actor
  design. Fixed alarm-safety's **BLOCKER** (the `Int` overflow trap → kept in `Double`), applied the
  **narrowed catch** (isConflict + rollback for the expected loser; genuine faults fail closed), and
  added the no-trap / whole-second / cross-alarm tests + this fail-closed/migration documentation.
- **Handoff (scope — the primitive, not the wiring).** WG-089 delivers the de-dup **mechanism**; the
  actual app-launch/foreground entry point that calls `surface` (and routes the WG-088 `work` pipeline
  through the same coordinator) is a **composition follow-on**, exactly like WG-088's `BGTaskScheduler`
  registration — it constructs `CoreDataPreAlarmPromptLedger` in `AppEnvironment` and cancels an
  in-flight BG evaluation when the app foregrounds. "App launch evaluates without duplicate prompting"
  is proven at the mechanism + unit-test level here; the launch path is that follow-on.

### WG-081 (2026-08-09): Recent movement history query

- **What it is.** `RecentMovementQuery` (pure, Foundation-only, `MotionDomain`) turns the WG-062
  historical pedometer into a `RecentMovementSnapshot` — a recent step count + a recency upper bound +
  a `sourceAvailable` flag — the recent-movement half of what WG-082 (pre-alarm evaluator) will feed
  the WG-080 model. `now` is injected (no clock read); the snapshot is a pure value with no alarm
  authority, so recent-movement evidence can never by itself suppress an alarm (#8).
- **No continuous overnight sensing (acceptance).** The query depends **only** on the bounded-window
  historical port (`HistoricalPedometerSource.samples(in:)`, one-shot `CMPedometer.queryPedometerData`
  which returns up-to-7-days of stored history without the app running) — never the live stream, no
  `BGTaskScheduler`, no background sensing. A snapshot issues one `availability()` check + at most
  `recencyLadderSeconds.count` (default 3) bounded queries on demand, right before the alarm.
- **Bounded window (acceptance).** Every query window is built through WG-062's `PedometerQueryWindow`
  (finite, ordered, `end <= now`, span `<= 24 h`). The recency **ladder** ([180, 600, 1800] s by
  default) is sanitised — non-finite / ≤0 rungs dropped, each clamped to `maxSpan`, deduped, and
  **capped to the widest `maxLadderRungs` (8)** so a pathological config can't fan out into unbounded
  I/O. The widest rung bounds the step count; the tightest rung still containing a step sets recency.
- **Clock changes & stale samples (acceptance).** Fail-closed on a non-finite clock (→ `.empty`).
  `stepCount(in:)` re-checks **every** sample against the *current* `now`-derived window — a
  backward clock jump (a now-future-stamped sample) or a forward jump (a now-stale sample) is dropped,
  so neither can fabricate "recent movement". This re-check is **deliberately redundant** with the
  adapter's `PedometerSample.validated` (it re-tests against the *new* window and guards fakes) — a
  comment forbids DRYing it away and reopening the clock-jump hole. Step sums **saturate** (no
  overflow trap; the WG-080/068 lesson).
- **Recency is honest but coarse — pinned residual.** Aggregate history exposes only a per-window
  count stamped at the window end (constant `endDate == now`), not a precise last-step time, so the
  ladder infers recency from *which nested window's count is non-zero* and recency is **quantized to
  the rungs** (a step 181 s ago reports 600, not ~181; `testRecencyIsRungQuantizedKnownLimitation`).
  It is an honest **upper bound** that never under-reports (a step 200 s ago can never read ≤180 s,
  verified against both the real-adapter per-window-count mechanism and the fake). The
  `HistoricalPedometerSource` doc now states the aggregate-coverage / monotonicity contract the ladder
  relies on. Per-sample `quality` is intentionally collapsed (CMPedometer history is authoritative
  `.high` — WG-062); quality-weighting is out of scope for the historical path (recorded here).
- **`sourceAvailable` — "couldn't observe" ≠ "confirmed still".** An unavailable / transient-failure
  source fails closed to zero steps like a genuine still night, but the snapshot now carries
  `sourceAvailable` so WG-082 can treat "sensor unavailable" differently from "confirmed still" —
  both keep the alarm (#8), but a safety-sensitive evaluator should not present them identically.
- **Review (motion-red-team + ios-architect, read-only). No BLOCKER** — red-team confirmed stale /
  replay / clock-jump can't fabricate movement, the ladder is an honest upper bound, it's one-shot,
  and #8 holds structurally; ios-architect confirmed domain purity, Clock injection, Sendability, and
  determinism. Applied: the `sourceAvailable` field (the "most consequential" API gap — couldn't-
  observe vs confirmed-still), a `Task.isCancelled` break so cancellation yields the honest widest
  bound instead of a silently-loosened one, a window-aware fake + tests for the real-adapter mechanism
  + the two-burst tightest-rung case + the pinned quantization residual, the port aggregate-contract
  doc, the rung-count cap, the quality-collapse decision, and the deliberate-redundancy comment.
  **Handoff:** WG-082 combines this snapshot (recent steps + recency + availability) with a
  sustained-episode source and device interaction into the WG-080 model, then applies criticality +
  time-remaining prompt policy — movement never directly cancels.
