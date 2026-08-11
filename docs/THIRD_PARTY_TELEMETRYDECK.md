# Third-Party Assessment — TelemetryDeck (WG-272)

Required by the CLAUDE.md rule: *"No third-party SDK without a written privacy and maintenance assessment."*
This is that assessment for **TelemetryDeck**, the only third-party dependency proposed for the app (see
`docs/TELEMETRY_PLAN.md` and the WG-272 ADR in `docs/DECISIONS.md`).

## 1. What it is

- **Purpose:** opt-in, privacy-first product + reliability + crash analytics for Apple-platform apps.
- **SDK:** `github.com/TelemetryDeck/SwiftSDK`, Swift Package Manager, product `TelemetryDeck`. Pin to an
  exact `from:` version; bump deliberately.
- **Integration surface:** one adapter (`TelemetryDeckSink: AnalyticsSink`) in `AppComposition`. The domain
  and `Observability` never import it. The app talks to the closed `AnalyticsEvent` port; only the adapter
  knows TelemetryDeck exists.

## 2. Data flows

- **What is sent:** the closed `AnalyticsEvent` set only — flags, closed-enum categories, bucketed ints
  (see `docs/TELEMETRY_PLAN.md` §4) — plus crash metadata. **No free text** is representable by the schema,
  so no health sample, location, alarm label, calendar title, journal text, or LLM prompt can be sent.
- **Identifier:** a **salted hash** of identifier-for-vendor — anonymous, non-reversible, per-install. No
  IDFA, no ATT prompt, no cross-app identity.
- **Transport:** the SDK batches signals and uploads over HTTPS on its own queue (fire-and-forget). The app
  never blocks on it; an offline device or upload failure is swallowed.
- **When:** only while the user has **opted in** (`analyticsEnabled == true`, default false). The
  `GatedAnalytics` wrapper drops every event when off.
- **Direction:** send-only. The App ID is a publishable write key; it cannot read data back.

## 3. Privacy & legal posture

- `NSPrivacyTracking` stays **false** (no cross-app/website tracking). Declared collected types:
  `Product Interaction` + `Crash Data`, both **not linked** to identity, **not** used for tracking, purpose
  App Functionality/Analytics.
- **Hosting:** EU (Germany). Residency analysis for US / India / EU in `docs/TELEMETRY_PLAN.md` §10 — the
  anonymity + aggregation keeps it out of most personal-data regimes. Not legal advice.
- **Consent:** explicit opt-in via a dedicated onboarding step + a Privacy-settings toggle; honored live;
  off is the kill-switch.
- **GDPR:** TelemetryDeck positions itself as GDPR-friendly (anonymous, aggregated, EU-hosted, DPA
  available). Sign the DPA at account setup.

## 4. Maintenance

- **Footprint:** a small, single-purpose SDK — far lighter than Firebase/Sentry. One adapter file to own.
- **Update cadence:** review the pinned version each release; bump only with a changelog read + `make
  ci-fast` green. No auto-major-bumps.
- **Removal plan (low lock-in):** because everything is behind `AnalyticsSink`, removal is (1) swap the
  production sink back to `NoOpAnalyticsSink`, (2) drop the SPM package + `TelemetryDeckSink.swift`, (3)
  revert the nutrition-label/manifest disclosure. No call sites change — they depend on the port, not the
  SDK. The app returns to zero-transmission with no domain edits.
- **Failure mode:** the SDK failing, being unavailable, or the network being down has **no** effect on the
  app — telemetry is best-effort and off the critical path. There is no runtime dependency on it.

## 5. Residual risks & mitigations

| Risk | Mitigation |
|---|---|
| A future dev adds a free-text event | The closed enum has no free-text case; a leak-scan test (WG-276/278) fails the build if a case can carry sensitive data |
| Telemetry delays an alarm | Fire-and-forget; a critical-path-isolation test (WG-278) proves emissions never block scheduling/reconcile/challenge |
| Silent opt-in / disclosure drift | Off by default; disclosure pins in `PrivacyNutritionLabelTests` + `PrivacyManifestTests` must stay consistent (WG-277) |
| App ID mistaken for a secret | It is a publishable write key, stored as build config; `SecretHandlingAuditTests` stays clean |
| Vendor/residency change | Self-host is the documented fallback; removal is a 3-step, no-call-site-change operation |

## 6. Verdict

Adopt, **gated on WG-272 approval (recorded)**, because: single-purpose and light to maintain, structurally
incapable of transmitting sensitive data (closed schema), anonymous + off-by-default + consented, off the
critical path, and trivially removable. It is the right-sized tool for a privacy-positioned safety app —
unlike Firebase/GA, which were rejected.
