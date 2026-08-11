# Epoch 13 (WG-252): Final regression after fixes

The capstone of E13 (adversarial review). After the fixes across WG-240–251, the full available automated
suite was re-run as the authoritative regression.

## Result

`make ci-fast` — **1208 tests, 0 failures, 0 unexpected, 0 warnings; SwiftLint 0, swift-format clean; build
clean.** `** TEST SUCCEEDED **`.

This is the unit + integration suite (the deterministic core, adapters behind fakes, and every source-scan
pin). The XCUITest scheme (`make test-ui`) and the on-device matrix are **out of scope** for automated
regression here — the UI flows are largely unhosted pending E14 composition, and device behavior (AlarmKit
ring-through-silent, battery, latency) needs real hardware (WG-030). Both are recorded as gating in
`docs/RELEASE_CHECKLIST.md`.

## E13 epics — what the adversarial review delivered

Thirteen epochs (WG-240–252). Test count 1185 (E12 end) → **1208**. Every epoch produced CI regression pins;
the ones that found genuine gaps also produced fixes:

| Epoch | Focus | Outcome |
|---|---|---|
| WG-240 | Invariant map | 50-invariant → code → test map; no open P0; P1 (anti-shake) assigned to 243 |
| WG-241 | Functional bug hunt | **Fixed** critical-status masking + conversational double-commit |
| WG-242 | Time/DST/travel | **Fixed** `Etc/GMT±N` acceptance (#11); fall-back anti-double-fire test |
| WG-243 | Motion spoofing | **Fixed** the #19/#20 anti-shake gate (corroboration required to pass) |
| WG-244 | Background/race chaos | **Fixed** reconcile lost-update (silent no-ring) via re-validation |
| WG-245 | AI injection | No live exploit; **pinned** the validated NL-create carriers criticality-free |
| WG-246 | Privacy/security | **Fixed** prompt-render redaction + leak-scan hole; refreshed threat model |
| WG-247 | Accessibility | **Fixed** destructive-consequence announcement + Reduce-Motion throttle |
| WG-248 | Aesthetic polish | **Fixed** primary-CTA style + raw fonts; corrected visual-regression docs |
| WG-249 | Battery/perf | **Added** hot-path perf bound + HealthKit no-continuous-observation locks |
| WG-250 | App Store preflight | NOT submittable; **pinned** the privacy-control false-assurance gap |
| WG-251 | RC bug bash | E13 fixes coherent; **fixed** diagnostics `stale`/`skipped`, fail-closed reconcile, doc hazard |
| WG-252 | Final regression | This document — full suite green |

## Release state

**The deterministic safety core is release-candidate quality and regression-locked.** Every one of the 50
safety invariants maps to enforcing code and a pinned test (WG-240), and E13 added lost-update,
injection-carrier, prompt-redaction, accessibility, aesthetic, perf/battery, and compliance locks on top.

**Shipping is gated on two things, neither a defect in the logic that exists:**

1. **E14 composition wiring** — the challenge ring-stop, `SystemTimeZoneMonitor`, the diagnostics provider,
   and the `DataEraser`/retention runner + export/deletion/consent/conversational screens (the WG-250 App
   Store submission blockers), plus the live sensor adapters, are built + unit-tested but not composed into
   `AppEnvironment`/`RootView`. Tracked, with the WG-250 expected-failure gate that flips red the moment the
   privacy controls are wired.
2. **On-device verification (WG-030)** — AlarmKit ring-through-silent/Focus, critical-confirm, and absolute
   battery/latency budgets.

E13 (adversarial review) is complete: **13/13 epochs**, every fix regression-pinned, the suite green and
warning-free, and every outstanding gap explicitly tracked to E14 or the device matrix rather than left
silent.
