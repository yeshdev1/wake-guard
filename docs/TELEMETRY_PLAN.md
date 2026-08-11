# WakeGuard — Telemetry Plan (TelemetryDeck)

Status: **decisions locked 2026-08-11 (see §8) — awaiting go on WG-272 (the ADR)**. This plan adds opt-in,
privacy-first product + reliability + crash telemetry via **TelemetryDeck**, behind the existing
`AnalyticsSink` port (WG-220). It ships **off by default**, discloses collection, and never touches the
alarm critical path. No code in this plan is implemented yet.

> Two hard gates before any of this merges:
> 1. **Disclosed + opt-in.** "No *hidden* analytics" is a standing quality rule and the nutrition label
>    currently promises *nothing* is transmitted. Telemetry must be consented, off by default, and disclosed.
> 2. **An ADR + explicit human approval** to change the pinned privacy assertions (nutrition label, privacy
>    manifest, `PrivacyNutritionLabelTests`, `PrivacyManifestTests`). Per CLAUDE.md we never weaken a pinned
>    privacy/safety assertion without an ADR and sign-off. This plan *is* the pre-ADR; the ADR lands in
>    `DECISIONS.md` at Phase 1.

---

## 1. Why TelemetryDeck (and not Firebase/GA)

TelemetryDeck is an Apple-platform-native, privacy-by-design analytics service:

- **No IDFA, no ATT prompt, no cross-app tracking.** The default signal identifier is a *salted hash* of the
  identifier-for-vendor — anonymous and non-reversible — so `NSPrivacyTracking` stays **false**.
- **Aggregated by design**, GDPR-friendly, EU hosting. No advertising ecosystem attached.
- **Tiny SDK** (`github.com/TelemetryDeck/SwiftSDK`, product `TelemetryDeck`) — small maintenance surface.
- **Fire-and-forget**: `TelemetryDeck.signal(_:)` enqueues and returns; the SDK batches + uploads on its own
  queue, so it is off the critical path by construction.

Firebase/GA were rejected: Google ad ecosystem on a sleep/health app, a **free-form** event model that
would reopen the sensitive-payload hole our closed enum closes, an ATT prompt, and a heavy SDK. (See the
`DECISIONS.md` entry to be written.)

---

## 2. What already exists (so this is an adapter, not a refactor)

- **`Sources/Observability/Analytics.swift`** — the port is built:
  - `AnalyticsSink` protocol (`func record(_ event: AnalyticsEvent)`).
  - `AnalyticsEvent` — a **closed** enum; every case carries only flags / closed-enum categories / bucketed
    ints. **No free-text case exists**, so sensitive payloads are *structurally* impossible.
  - `AnalyticsValue` — `.flag(Bool) | .bucket(Int) | .category(String-from-closed-enum)`.
  - `GatedAnalytics` — wraps a sink, drops everything when disabled.
  - `NoOpAnalyticsSink` — the default; records nothing.
- **`Sources/AlarmDomain/AppSettings.swift`** — `analyticsEnabled: Bool` exists, **default `false`**.
- **`RecordingAlarmCommandProcessor`** (`Sources/AppComposition/DiagnosticsWiring.swift`) — an existing
  decorator over `AlarmCommandProcessing` that already observes every `reconcile()`. This is the clean seam
  for reliability events — no change to the core processor or the AI layer.

What is **missing** (the actual work):
- No `AnalyticsSink` is wired into `AppEnvironment` (the port has **zero** production call sites).
- `analyticsEnabled` is a **dormant** field — no consent toggle in onboarding or Privacy settings.
- The nutrition label + `PrivacyInfo.xcprivacy` declare **no** collection; both must change.
- TelemetryDeck would be the project's **first** SPM dependency (no `packages:` in `project.yml` yet).

---

## 3. Architecture

```
call sites (UI models, RecordingProcessor, coordinators)
      │  record(AnalyticsEvent)              ← closed enum, no free text
      ▼
GatedAnalytics(isEnabled: consent snapshot) ← drops all when consent off
      │
      ▼
TelemetryDeckSink : AnalyticsSink            ← NEW adapter (AppComposition)
      │  maps case → TelemetryDeck.signal("name", parameters:[coarse])
      ▼
TelemetryDeck SDK (SPM)  →  batched HTTPS upload (off critical path)
```

- **Adapter placement.** `TelemetryDeckSink` lives in **`AppComposition`** (allowed to import third-party);
  `Observability` stays pure. The domain never sees TelemetryDeck.
- **The consent-gate detail (important).** `GatedAnalytics.isEnabled` is **synchronous**
  (`@Sendable () -> Bool`) but settings are **async**. Introduce a tiny `ConsentFlagBox` — a `Sendable`
  reference type wrapping a lock-guarded `Bool` — seeded in `make()` from the loaded `AppSettings` and
  updated whenever the toggle writes. The gate closure reads it synchronously. This keeps the consent
  decision live without an `await` on the hot path.
- **DI wiring (mirrors this session's composition pattern).** Add `let analytics: any AnalyticsSink` to
  `AppEnvironment` → add to `SystemWiring` (prod: `GatedAnalytics(TelemetryDeckSink(...))`; test/preview:
  `NoOpAnalyticsSink`) → both `production()` / `inMemory()` factories → construct in `make()` → memberwise
  init. Views read it via `environment.analytics`.
- **App ID.** TelemetryDeck's app ID is a *publishable* write key (send-only, ships in the binary), not a
  secret — but treat it as config. Add it in `project.yml → targets.WakeGuard.settings.base` as
  `INFOPLIST_KEY_TelemetryDeckAppID: "<uuid>"` (next to the bundle ID / versions / usage strings); the sink
  reads `Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID")` at composition. Not a hardcoded
  literal, so `SecretHandlingAuditTests` stays clean and staging/prod can differ. Optional stricter variant:
  a gitignored `Config/Secrets.xcconfig` + committed `Secrets.example.xcconfig`.

---

## 4. Event schema (the closed enum, extended)

Keep everything **coarse**: flags, closed enums, and bucketed counts only — never a label, time, count that
fingerprints, or any raw field. Existing product events stay; add the **reliability** events that actually
matter for a safety alarm app.

| Event | Payload (coarse only) | Purpose |
|---|---|---|
| `alarmCreated(isCritical:)` *(exists)* | flag | adoption of critical alarms |
| `agentChangeApplied(confirmed:)` *(exists)* | flag | AI-proposed changes accepted vs auto |
| `challengeFinished(passed:)` *(exists)* | flag | walk-challenge pass rate |
| `onboardingCompleted(skippedFirstAlarm:)` *(exists)* | flag | onboarding funnel |
| `optionalFeatureToggled(feature:enabled:)` *(exists)* | closed enum + flag | which optional data users enable |
| `dataExportPrepared` / `dataDeleted(scope:)` *(exists)* | — / closed enum | privacy-control usage |
| **`alarmScheduled(isCritical:)`** *(new)* | flag | scheduling volume (reliability denominator) |
| **`reconcileOutcome(category:)`** *(new)* | closed enum `{matched, repaired, skipped, failed}` | **the key reliability signal** — divergence/repair rate |
| **`permissionResolved(kind:granted:)`** *(new)* | closed enum + flag | denied-permission rates that degrade features |
| **`appLaunched`** *(new)* | — | active-install denominator |

Deliberately **excluded** for now: `alarmRingObserved` (real ring detection is device-only AlarmKit
observation, WG-030 — no clean call site yet; revisit once that hookup exists). No timing/latency events
(would risk fingerprinting) — battery/latency stay in Apple's Organizer.

**Crash reporting (adopted, decision §8.3).** TelemetryDeck crash capture is enabled at init. Crash payloads
carry crash metadata only; the app never logs health/location/labels/journal/prompt text, so none can appear.
This also feeds the on-device `recentErrors` in Diagnostics (currently always empty), so a user's shared
diagnostics report becomes actionable. Declared as `Crash Data` in the manifest + nutrition label.

Each new case gets a `name` + coarse `properties` in `AnalyticsEvent`, reviewed against the leak-scan.

---

## 5. Granular task breakdown

Proposed backlog IDs **WG-272 … WG-279** (register in `BACKLOG.md` + `IMPLEMENTATION_STATUS.md` once
approved). Ordered by dependency.

### WG-272 — ADR + third-party assessment (no product code)
- Write the `DECISIONS.md` ADR: vendor choice, rejection of Firebase/GA, off-by-default + consent model,
  the closed-schema guarantee, the critical-path rule.
- Write the CLAUDE.md-required **third-party privacy & maintenance assessment** for TelemetryDeck
  (`docs/THIRD_PARTY_TELEMETRYDECK.md`): data flows, retention, subprocessors, SDK size, update cadence,
  removal plan.
- **Acceptance:** ADR merged; assessment doc exists; **human approval recorded** to proceed.
- **Gate:** nothing else starts until this is signed off.

### WG-273 — Add the SPM dependency
- Add top-level `packages:` to `project.yml` with `TelemetryDeck` pinned to an exact `from:` version; add
  `- package: TelemetryDeck` to the `WakeGuard` target `dependencies:`. Run `make generate`.
- **Acceptance:** project resolves + builds with the package; `Package.resolved` committed;
  `make ci-fast` green. No behavior change yet (sink not wired).

### WG-274 — `TelemetryDeckSink` adapter (wired, still off)
- New `Sources/AppComposition/TelemetryDeckSink.swift`: `struct TelemetryDeckSink: AnalyticsSink` mapping
  each `AnalyticsEvent` → `TelemetryDeck.signal(name, parameters:)`; initialize the SDK once at composition
  with the App ID from config and **crash reporting enabled** (decision §8.3).
- Add `ConsentFlagBox` (lock-guarded Sendable Bool).
- Wire into `AppEnvironment`: `analytics = GatedAnalytics(underlying: TelemetryDeckSink(...), isEnabled:
  consentBox.value)`; **prod only**. `inMemory()` → `NoOpAnalyticsSink`.
- **Acceptance:** graph builds; with `analyticsEnabled == false` (default) **nothing is emitted** (unit
  test asserts the gate drops all); adapter maps every case; app ID read from config, not literal.

### WG-275 — Consent UX (opt-in, honored live)
- Add an **opt-in** Toggle bound to `analyticsEnabled` in `PrivacySettingsView` **and** a **dedicated
  onboarding consent step** (its own screen, decision §8.2), with honest copy ("Help improve WakeGuard —
  share anonymous, aggregated usage and crash reports. Off by default. No health, location, alarm labels, or
  personal data is ever sent."). The screen offers a clear decline that leaves telemetry off.
- On write: `settingsRepository.save(...)` **and** update `ConsentFlagBox` so the gate flips immediately;
  seed the box from settings at launch.
- **Acceptance:** toggling on then off is honored on the next `record` with no relaunch (test); default
  remains off; VoiceOver/Dynamic Type/localized copy per UI rules.

### WG-276 — Instrument call sites (reliability + product)
- Extend `AnalyticsEvent` with the four new cases (§4).
- Emit **fire-and-forget** at: `RecordingAlarmCommandProcessor.reconcile` → `reconcileOutcome`; the
  create/agent flows → `alarmScheduled` / `alarmCreated` / `agentChangeApplied`; challenge runtime →
  `challengeFinished`; authorization coordinators → `permissionResolved`; onboarding → `onboardingCompleted`;
  export/delete coordinators → their events; app launch → `appLaunched`.
- **Acceptance:** each emission is off the critical path (never `await`-blocks an alarm/challenge/schedule);
  a leak-scan test proves no new case can carry sensitive data; suite green.

### WG-277 — Disclosure: nutrition label + privacy manifest
- Update `Sources/PrivacyDomain/PrivacyNutritionLabel.swift`: rewrite the line 65 promise; add transmitted
  "Product Interaction / Usage Data" **and** "Crash Data" entries — anonymous, aggregated, opt-in, not linked
  to identity, not used for tracking; update `transmittedDataTypes`.
- Update `PrivacyInfo.xcprivacy`: add `NSPrivacyCollectedDataTypes` entries
  `NSPrivacyCollectedDataTypeProductInteraction` **and** `NSPrivacyCollectedDataTypeCrashData` (both
  `Linked=false`, `Tracking=false`, purpose = App Functionality/Analytics); keep `NSPrivacyTracking`
  **false**; add TelemetryDeck's ingest host to `NSPrivacyTrackingDomains` **only if** required (it is not,
  since tracking=false).
- Update `PrivacyNutritionLabelTests` + `PrivacyManifestTests` to the new, honest state — **this is the
  pinned-assertion change that requires the WG-272 ADR + sign-off.**
- **Acceptance:** label + manifest + tests consistent and honest; `make ci-fast` green.

### WG-278 — Test matrix (see §7)
- Consent on/off honored live; structurally-no-sensitive-payload; offline degrades silently; never blocks a
  critical path; manifest/label pins updated; app-ID-from-config.
- **Acceptance:** all pass in `make ci-fast`; add a manual real-device line to the checklist (verify a
  signal actually lands in the TelemetryDeck dashboard on device — off-device it won't).

### WG-279 — Rollout, kill-switch, docs
- Confirm the consent toggle **is** the kill-switch (off → zero emission). Document a remote-free disable
  (ship an update flipping the default / removing init) — the app has no backend, so there is no server
  kill-switch; state that explicitly.
- Update `RELEASE_CHECKLIST.md`, `TESTABILITY_REPORT.md`, and the App Store Connect **data-collection
  questionnaire** answer. Complete the external privacy-policy update.
- **Acceptance:** checklist + questionnaire updated; App Store answers match the manifest/label.

---

## 6. Compliance artifacts touched (all must stay mutually consistent)

| Artifact | Change | Pinned by |
|---|---|---|
| `PrivacyNutritionLabel.swift` (line 65 + `transmittedDataTypes`) | "no analytics transmitted" → opt-in anonymous usage | `PrivacyNutritionLabelTests` |
| `PrivacyInfo.xcprivacy` | add `NSPrivacyCollectedDataTypes` entry; tracking stays false | `PrivacyManifestTests` |
| App Store Connect data questionnaire | declare usage-data collection (not linked, not tracking) | external / manual |
| External privacy policy | describe telemetry + opt-in | external / manual |

Other scan tests to re-run/verify (should stay green if the schema discipline holds): `PrivacyLeakScanTests`,
`SecretHandlingAuditTests`, `SecurityAuditTests`, `AnalyticsTests`, `SettingsRepositoryContractTests`,
`CrashDiagnosticsTests`.

---

## 7. Test matrix (WG-278 detail)

- **Consent gate:** `analyticsEnabled=false` ⇒ 0 signals; flip to true ⇒ subsequent events pass; flip back
  ⇒ dropped again — all without relaunch.
- **Structural leak-proof:** property-style test enumerating `AnalyticsEvent.allCases`-equivalent — every
  `properties` value is `.flag`, `.bucket`, or `.category` from a closed enum; **no** `.category` derived
  from user text. (Reinforces the existing WG-220 guarantee for the new cases.)
- **Critical-path isolation:** emitting an event never delays/blocks `process` / `reconcile` / challenge
  completion (the sink call returns synchronously; assert no `await` on the alarm path; a throwing/slow fake
  sink does not change alarm outcomes).
- **Offline / failure:** a failing upload is swallowed by the SDK; the app is unaffected (fake sink throws →
  no propagation).
- **Disclosure consistency:** label ↔ manifest ↔ `transmittedDataTypes` agree; tracking flag false.
- **Config, not secret:** app ID sourced from build config; `SecretHandlingAuditTests` clean.
- **Manual (device, WG-030):** a real signal appears in the TelemetryDeck dashboard from a device build with
  consent ON (cannot be verified in the simulator/CI).

---

## 8. Decisions (locked 2026-08-11)

1. **Event scope** — ship **all** §4 events at launch (product + the four reliability events).
2. **Onboarding** — a **dedicated consent step** (its own screen), not folded into the privacy step.
3. **Crash reporting** — **adopt** TelemetryDeck crash capture. This also populates the currently-empty
   `recentErrors` in Diagnostics (closes that WG gap). Adds `NSPrivacyCollectedDataTypeCrashData` to the
   manifest + a crash line to the nutrition label. Crash reports carry crash metadata only — the app never
   puts health/location/labels/journal/prompt text in logs, so none can appear in a crash payload.
4. **Hosting** — TelemetryDeck **managed EU**. Acceptable for US **and** India users (see §10 — anonymous/
   aggregated data, neither jurisdiction mandates local storage for it). Self-host is noted in the ADR as a
   fallback only if a future legal review requires localization.
5. **App ID** — user creates the TelemetryDeck app + app ID (external step). Stored as **build config**, not
   a literal: `project.yml → settings.base → INFOPLIST_KEY_TelemetryDeckAppID`, read at composition via
   `Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID")`. It is a **publishable write key**, not a
   secret, so committing it is acceptable; a gitignored `Config/Secrets.xcconfig` is an optional alternative.

---

## 9. What I will NOT do without your explicit go

- Flip `analyticsEnabled` default to true (it stays **off**).
- Change the nutrition label / privacy manifest / their pinned tests before the WG-272 ADR is approved.
- Add the SPM dependency before you confirm TelemetryDeck (WG-273).

---

## 10. Data residency (US / India / EU)

TelemetryDeck managed hosting is **EU-only**. That is acceptable for a global user base — including the US
and India — primarily because the collected data is **anonymous and aggregated** (a salted-hash signal id,
no raw identifiers), which keeps it out of most personal-data regimes entirely.

- **United States.** No general data-residency law; EU storage is fine and GDPR-grade protection is a
  superset. CCPA/CPRA govern disclosure + opt-out of sale/share, not location — satisfied here (opt-in,
  anonymous, never sold).
- **India (DPDP Act 2023).** Uses a **blocklist** transfer model (allowed unless the destination is
  government-barred; the EU is not), and governs *personal data* — anonymous aggregate telemetry likely
  falls outside it. Localization mandates are sector-specific (e.g., RBI payments), not applicable here.
- **EU/EEA (GDPR).** Data stays in-region; opt-in consent + privacy-policy disclosure cover the basis.

**Not legal advice.** India's DPDP rules were still being operationalized as of 2025. Posture the plan
takes: keep telemetry anonymous, disclose EU processing in the privacy policy, opt-in only. If the app ever
collects identifiable data or expands scope, obtain a jurisdiction-specific privacy-law review. **Self-host**
(ADR fallback) is the lever if a future review ever requires local storage.
