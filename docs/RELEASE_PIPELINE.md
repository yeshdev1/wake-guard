# Release pipeline — internal TestFlight (WG-260)

The repeatable path from a green commit to an internal TestFlight build. The **config + metadata +
archive/export** steps are automated in the `Makefile`; **code signing and the App Store Connect upload**
need real Apple Developer credentials on a provisioned machine, so they are the manual step (documented
below) — the same posture as the on-device verification tasks (WG-030).

## One-time setup

- An Apple Developer account with the app record `com.wakeguard.app` created in App Store Connect.
- Set the Team ID in `ExportOptions.plist` (`REPLACE_WITH_TEAM_ID`) and enable automatic signing for the
  team (or supply a distribution profile).
- For automated upload: an App Store Connect API key (Issuer ID + Key ID + `.p8`), stored outside the repo.

## Steps

1. **Verify green.** `make ci-fast` (or `make ci`) — build clean, 0 warnings, lint + format clean, full
   suite green. Never archive a red build.
2. **Generate build metadata + release notes.** `make release-notes` prints the version, the reproducible
   build number, commit, branch, date, and the release notes (commit subjects since the last tag — subjects
   only, so no sensitive body text leaks). `scripts/release_metadata.sh` is the generator.
3. **Archive.** `make archive` builds a device archive at `build/WakeGuard.xcarchive`, stamped with the
   build number (`CURRENT_PROJECT_VERSION`). Override per upload with `make archive BUILD=<n>`; the default
   is the commit count, so re-archiving the same commit is reproducible.
4. **Export.** `make export` produces a signed `.ipa` under `build/export/` via `ExportOptions.plist`
   (`method: app-store-connect`, `uploadSymbols: true`) — **once the Team ID and signing are configured**
   (with the placeholder `teamID`, `-exportArchive` fails, by design). Run `make archive` immediately
   before `make export` so the `.ipa` is the current build (both steps clear stale output first).
5. **Upload (manual — needs credentials).** From a provisioned machine:
   `xcrun altool --upload-app -f build/export/WakeGuard.ipa --apiKey <KeyID> --apiIssuer <IssuerID>`
   (or Transporter / an App Store Connect API CI action). This is the step this sandbox cannot run.

## Build metadata

- **Version:** `MARKETING_VERSION` in `project.yml` (currently `1.0.0`) — the source of truth (XcodeGen).
- **Build number:** the commit count on `HEAD` (`git rev-list --count HEAD`) — monotonic and reproducible;
  override with `BUILD=`. A release CI job **must check out full history** (`actions/checkout` with
  `fetch-depth: 0`); on a shallow clone the count is wrong (and App Store Connect rejects a build number
  that isn't strictly greater than the last upload), so `release_metadata.sh` **fails loudly** rather than
  emit a bogus number.
- Both are explicit in `project.yml`, so an archive's metadata is deterministic rather than defaulting to
  `1.0`/`1`.

## Debug tools are absent from release

Every debug-only affordance is `#if DEBUG`-gated, so a release archive compiles it out:

- `MotionInfrastructure/MotionTraceRecorder.swift` — the WG-075 calibration trace recorder; the **whole
  file** is `#if DEBUG`, so shipping code can't even reference it.
- The `-uiTesting` isolated-in-memory-store launch hook in `WakeGuardApp.swift` — `#if DEBUG` only; launch
  arguments can't be injected into a shipped app regardless.

`ReleaseReadinessTests` pins both (and the version/export/metadata config), so a change that would leak a
debug tool into release — or drop the release config — fails `ci-fast`.

## Internal TestFlight ≠ App Store submission

An **internal** TestFlight build (this pipeline) is for the team and testers: on-device verification
(WG-030), the reliability/travel/motion/AI betas (WG-262–265), and dogfooding. It does **not** require the
app to be feature-complete or submittable.

**App Store submission (WG-268) is separately gated** by the WG-250 preflight blockers — the privacy-control
wiring (export/deletion/retention + routing) and the App Review notes pointing only at reachable screens —
plus on-device verification. Those are tracked in `docs/RELEASE_CHECKLIST.md` (Submission blockers) and must
clear before a public release, not before an internal build.
