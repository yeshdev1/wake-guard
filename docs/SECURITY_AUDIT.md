# Static security & dependency audit (WG-189)

Checked by `SecurityAuditTests`, so the inventories below stay matched to the code.

## Dependency audit

**Zero third-party dependencies** (WG-186): first-party Swift + Apple system frameworks only, no SPM /
CocoaPods / Carthage. There are therefore **no known-vulnerable dependencies** to patch or justify, and
nothing to remove. Any future dependency requires a written privacy + maintenance + vulnerability
assessment before adoption.

## Network endpoint inventory

**The shipped app makes no outbound network calls.**

| Site | What | Endpoint |
|---|---|---|
| `AppComposition/SettingsOpeners.swift` | Opens the system Settings app via `UIApplication.openSettingsURLString` | URL **scheme** (`app-settings:`), not a network endpoint |
| `AIApplication/CloudProvider.swift` | `CloudModelTransport` is an **abstract protocol**; no concrete networked client ships | none (the optional cloud client is not built into the default app) |

There are no `URLSession`/`URLRequest` uses and no hardcoded `http(s)://` endpoints in `Sources/`. When a
concrete cloud client is added (optional cloud AI, WG-174), it will be the **only** outbound endpoint —
gated by the feature flag + separate consent, and sending only redacted `CloudSafeRequest` data.

## Entitlements inventory

`WakeGuard.entitlements` declares exactly one entitlement:

| Entitlement | Justification |
|---|---|
| `com.apple.developer.healthkit` | Read-only sleep access for the optional readiness estimate (WG-121). The app never writes Health data. |

No networking (client/server), associated-domains, keychain-sharing, or app-groups entitlements are
present.

## Findings & triage

| # | Finding | Severity | Triage |
|---|---|---|---|
| 1 | Three redaction vocabularies exist — `Cleared` (WG-181), the wired `CloudSafeText`/`CloudSafeRequest` transmit boundary (WG-174), and the Observability `Redacted` log marker (WG-019). | Low (design) | **Accepted.** `CloudSafeText` is **the** single wired transmit chokepoint; `Cleared` is a general primitive not on the transmit path; `Redacted` is the log boundary. If unified later, `CloudSafeText` should be derived from a `Cleared`. Documented; no code change required now. |
| 2 | `Cleared`'s redaction transform is caller-supplied; an identity transform passes raw content through (WG-181 review). | Low | **Accepted + mitigated.** Pinned as a known-unsafe hazard by a test; the reviewable surface is the few redact call sites. Revisit if `Cleared` ever becomes the wired transmit boundary. |
| 3 | No outbound network in the shipped app. | — | **No finding.** Confirmed by source scan; re-audit when a concrete cloud client is added. |

All findings are triaged; none are blocking.
