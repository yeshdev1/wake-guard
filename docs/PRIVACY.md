# Privacy manifest & SDK inventory (WG-186)

This document backs `PrivacyInfo.xcprivacy` (the Apple privacy manifest) and inventories every SDK the app
ships. It is kept in sync with the code by `PrivacyManifestTests`.

## SDK inventory

**WakeGuard ships zero third-party SDKs.** The app is first-party Swift plus Apple system frameworks only.
There are no Swift Package, CocoaPods, or Carthage dependencies (`project.yml` declares no `packages:`; the
only target `dependencies:` are internal test-bundle → app references).

| Dependency | Type | Data use | Justification |
|---|---|---|---|
| Apple system frameworks (SwiftUI, AlarmKit, Core Motion, Core Location, HealthKit, EventKit, UserNotifications, Core Data, Security, Foundation Models) | First-party OS | On-device only | Required for the app's core + optional features; each is permission-gated and wrapped behind a protocol. |

Because there are no third-party SDKs, there are **no unused SDKs to remove** and no external data-use
justifications to write. Any future SDK requires a written privacy + maintenance assessment before adoption
(project rule).

## Required-reason APIs

Declared in `PrivacyInfo.xcprivacy` under `NSPrivacyAccessedAPITypes`:

| API category | Reason code | Why |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Stores the last-known IANA time zone so alarms stay correct across travel (WG-102). Access is to information stored only by WakeGuard itself. |

No other required-reason APIs are used: no file-timestamp, system-boot-time, disk-space, or
active-keyboard APIs. The Keychain (cloud-token storage, WG-185) is **not** a required-reason API category.

## Tracking & collection

- `NSPrivacyTracking`: **false**. WakeGuard does not track users.
- `NSPrivacyTrackingDomains`: **empty**. No tracking domains are contacted.
- `NSPrivacyCollectedDataTypes`: **empty** in the default build. Health, motion, location, and calendar are
  processed **on device only** and never transmitted. Optional cloud AI (off by default, separate consent)
  transmits only minimized, redacted data — accounted for in the WG-187 nutrition-label mapping.
