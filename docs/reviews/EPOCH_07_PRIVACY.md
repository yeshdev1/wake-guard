# Epoch 7 (WG-246): Privacy & security data-flow review

A `privacy-security-reviewer` traced every sensitive category (health, motion, location, calendar, journal,
cloud token, LLM prompts) through collection → memory → persistence → logs → analytics → prompts → export →
deletion, verified the as-built data-flow against the code, and probed the source-scan pins for bypasses.

**Verdict: the privacy *logic* is correct and well-pinned; no sensitive raw value can reach a log,
analytics event, or the cloud.** The one **High** finding is a composition-wiring gap (export/deletion/
retention + privacy UI not routed), not a logic defect — tracked → E14. Two Low defense-in-depth gaps are
fixed here; the threat model is refreshed.

## Confirmed (enforcement → pin)

- **No sensitive raw value is logged (#41).** The single production sink is `SystemPrivacyLog` → `os.Logger`,
  fed only a compile-time `StaticString` + non-sensitive fields + category-only `Redacted` markers. A
  whole-`Sources` scan confirms `os_log`/`os.Logger`/`import os`/`OSLog` appear only in that sink and
  `print`/`NSLog`/`debugPrint`/`dump` nowhere. Sensor adapters redact at the source (location keeps only a
  timestamp; AlarmKit errors map to coarse reasons). Pins: `PrivacyLeakScanTests`, `PrivacyLogTests`.
- **Analytics coarse + off by default (#44).** `AnalyticsEvent` is a closed enum (no `custom(name:payload:)`);
  `GatedAnalytics` emits nothing when disabled; `analyticsEnabled == false` by default. Pins: `AnalyticsTests`.
- **No advertising use (#40); no third-party SDK.** Zero package deps; nutrition label sets
  `usedForTracking:false`/`linkedToIdentity:false`. Pins: `PrivacyNutritionLabelTests`, `PrivacyLeakScanTests`.
- **Cloud default-deny (#35).** `CloudSafeText` `fileprivate` init via `CloudRedactor.clear` only; transport
  accepts only `CloudSafeRequest`; both flags default off; token in Keychain wrapped in `Sensitive`. Pins:
  `CloudProviderTests`. (Confirmed: `CloudModelTransport` has **no concrete implementation** — no egress
  path is wired, recorded in the threat model.)
- **`Sensitive` can't be logged through normal APIs (WG-181).** Redacts through description/dump/Mirror; raw
  value only via the greppable `reveal()`. Pins: `SensitiveDataTests`.

## Fixed here (Low, defense-in-depth)

- **Finding 3 — `LanguageModelRequest` rendered its prompt verbatim.** The struct carried `systemPrompt`/
  `userPrompt` as bare `String`, so `"\(request)"`/`dump` would surface the (possibly untrusted/sensitive)
  prompt. Nothing logged it, but the type was unprotected. **Fix:** it now conforms to
  `CustomStringConvertible`/`CustomDebugStringConvertible`/`CustomReflectable`, exposing only field lengths
  — mirroring the `Sensitive` chokepoint. Pin: `PrivacyLeakScanTests.testLanguageModelRequestNeverRendersPromptContent`.
- **Finding 4 — leak-scan lexical hole.** `testOSLoggerIsConfinedToTheObservabilitySink` matched
  `os_log`/`os.Logger`/`import os`/`OSLog`; a bare `Logger(` instantiation (via an import spelling dodging
  those substrings) could evade it. **Fix:** the scan now also flags `Logger(` — a file must *construct* the
  logger regardless of how it imports, so the instantiation token closes the hole (the sanctioned
  `os.Logger(` sink matches but is allowlisted to `/Observability/`).

## Tracked (not fixed here)

- **Finding 1 (High) — export/deletion/retention + privacy UI unwired → E14.** `ExportBuilder`/
  `DeletionPolicy`/`RetentionPolicy` are correct and isolated-tested, **but** there is no production
  `DataEraser` over Core Data, no retention job runs, and the export/deletion/consent/diagnostics screens
  are not routed (`RootView` hosts only `AlarmListView`). So #42/#43 are **unmet at runtime** and contradict
  `PRIVACY_POLICY.md` / the nutrition label — a privacy-label/behavior mismatch that **blocks the WG-250 App
  Store preflight**. This is composition, scheduled for E14; recorded in the threat model with the
  reachability test to add (composition-graph + `PrivacyControlsReachableUITests`).
- **Finding 2 (Low) — `Sensitive` adopted only for the cloud token.** Health/location/calendar/journal raw
  values flow as bare types; WG-181's broad "structurally impossible to log" guarantee is unrealized (the
  type's own comment concedes this). No active leak — the guarantee rests on the lexically-pinned absence of
  `print`/`os_log`. Wrap sensitive values in `Sensitive` at each adapter boundary (WG-190 residue).
- **Finding 5 (Observation) — Analytics/Crash/PrivacyLog have no production call sites.** Safe (nothing
  emitted), consistent with off-by-default; re-run this review when observability is wired.

## Threat model refreshed

`docs/THREAT_MODEL.md` updated: E09 status corrected from "scaffolded" to implemented + tested (WG-245);
§3 rows cite the real constrained-decode/injection tests and the validated-carrier criticality pin; §4 gains
the LLM-prompt-redaction row and the **export/deletion-wiring gap** row; residuals note the missing cloud
transport and the E14 wiring gap.
