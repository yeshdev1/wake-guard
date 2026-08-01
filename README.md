# wake-guard

This is for waking up on time for lazy asses (yes I am talking to you).

WakeGuard is a safety-sensitive iOS alarm and circadian-wellness app. The core
is deterministic; AI is advisory and permission-gated. See `START_HERE.md` and
`docs/` for the product spec, architecture, safety invariants, and the backlog.

## Requirements

- Xcode 26+ / Swift 6, iOS 26 SDK (deployment target iOS 26 — ADR-001)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
  (the `.xcodeproj` is generated from `project.yml`, not committed)

## Build & test

```sh
make generate   # xcodegen generate  -> WakeGuard.xcodeproj
make build      # build the app for an iOS 26 simulator
make test       # run the unit-test suite
```

`make` targets auto-generate the project first. Override the simulator with, e.g.
`make test DESTINATION='platform=iOS Simulator,name=iPhone 17,OS=26.5'`.

## Layout

- `Sources/WakeGuardApp/` — app entry point and composition root (no business logic)
- `Sources/<Module>/` — one feature folder per architecture module (ADR-003)
- `Tests/WakeGuardTests/` — unit tests · `Tests/TestSupport/` — deterministic fakes (WG-007)
- `docs/` — spec, architecture, safety invariants, ADRs (`DECISIONS.md`), backlog
