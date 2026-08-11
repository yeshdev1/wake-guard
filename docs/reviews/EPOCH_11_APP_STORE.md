# Epoch 11 (WG-250): App Store compliance preflight

A `release-test-engineer` pass assessed submission readiness: privacy manifest, Info.plist usage strings,
entitlements, nutrition-label/policy accuracy, private-API/tracking checks, and the App Review notes.

**Verdict: NOT submittable today.** The static/document compliance layer is clean and pinned green, but two
**HIGH** blockers stand — both are the E14 composition-wiring gap surfacing at the store boundary. Critically,
all 28 existing compliance pins assert **document consistency, not runtime reachability**, so they are green
while the app is non-compliant. This preflight adds the pin that makes the gap CI-visible.

## Submission BLOCKERS (gating)

### BLOCKER 1 — Privacy-label/behavior mismatch: export/deletion/retention are documented but unwired

`PRIVACY_POLICY.md` and the nutrition label promise user export, deletion, and per-category retention, but at
runtime none exist: no production `DataEraser` conformance (only `FakeDataEraser` in tests), `RetentionCleanup`
has no production caller, and `DataExportView`/`DataDeletionView`/`ConsentCenterView` are never routed
(`RootView` hosts only `AlarmListView`). This is an App Review 5.1.1(v)/5.1.2 label-vs-behavior mismatch —
already flagged as WG-250-gating in WG-246. **Fix → E14:** implement a Core Data `DataEraser` + retention job
and route the privacy screens (or, if shipping without them, remove the promises from the docs — not the
intended path since the controls are built, just unwired).

### BLOCKER 2 — App Review notes point the reviewer at unrouted screens

`APP_REVIEW_NOTES.md` tells the reviewer to exercise the walk-challenge ring-stop, the natural-language
conversational screen, and "Settings → Permissions & privacy" — all three views are declared but never
instantiated, so the reviewer hits dead ends (Guideline 2.1, "app incomplete"). **Fix → E14:** route those
screens, or rewrite the notes to describe only the shipping flows (create/edit/delete/critical-confirm).

## PASS (compliant as of this build)

- **Info.plist usage strings** — every sensitive framework the code imports has a specific purpose string
  (`project.yml`): AlarmKit, Core Motion (disclaims location/health), Core Location When-In-Use
  (significant-change only), HealthKit share (read-only, "never a diagnosis"), Calendar full access
  (event-times-only). No placeholders.
- **Entitlements** — `WakeGuard.entitlements` declares only `com.apple.developer.healthkit`, matching the
  read-only HealthKit use; nothing claimed-but-unused or used-but-unclaimed. Critical alarms need **no**
  critical-alert entitlement (iOS 26 AlarmKit rings via the system-alarm baseline). Pin: `SecurityAuditTests`.
- **Privacy manifest** — declares no tracking (empty tracking domains + collected types) and the correct
  UserDefaults required-reason (`CA92.1`); no file-timestamp/boot-time/disk-space/keyboard required-reason
  APIs are used. Pin: `PrivacyManifestTests`.
- **No private API / no hidden analytics / no third-party SDK / no prompt leak** — `SecurityAuditTests`,
  `PrivacyLeakScanTests` green; zero package dependencies.
- **Privacy policy required content** present. Pin: `PrivacyPolicyRequirementsTests`.

## Fixed here — close the false-assurance gap

The reviewer's core finding: the 28 compliance pins are green while the app violates its own privacy label,
because they check doc-internal consistency, never runtime reachability. Added
`PrivacyManifestTests.testPrivacyControlsPromisedByDocsAreBackedByProductionCode`: if the privacy policy
promises deletion + export, a production (non-`Fake`) `DataEraser` conformance and a `RetentionCleanup` caller
must exist in `Sources/`. They don't yet, so it is an **`XCTExpectFailure`** — the suite stays green while the
BLOCKER is logged plainly ("WG-250 BLOCKER … unwired until E14"), and when E14 wires the controls the
assertions pass → `XCTExpectFailure` flips it to an *unexpected pass*, forcing removal of the wrapper. The
blocker can no longer be forgotten behind green pins.

## Tracked → E14 / device

- Wire `DataEraser` + retention runner + route the export/deletion/consent/diagnostics/challenge/conversational
  screens; add the `PrivacyControlsReachableUITests` (composition-graph + accessibility-id reachability) that
  WG-246 scoped — it would catch both blockers together.
- `wakeguard://` deep links (`RootView.onOpenURL`) and the opportunistic `BGTaskScheduler` are inert (no
  `CFBundleURLTypes` / `UIBackgroundModes`) — safe by design, but two documented behaviors don't fire.
- Device: AlarmKit ring-through-silent/Focus and the critical-confirm path are unverified (WG-030) — a
  TestFlight-on-device gate before submission.
