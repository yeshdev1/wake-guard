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
