# Travel Real-Device / Manual Simulation Matrix (WG-110)

WakeGuard's travel logic (E06) decides how an alarm behaves when the device time zone changes. Its
**deterministic core is fully unit-pinned** (see the "Automated pin" column); this matrix is the
**manual, on-device / simulator** pass that verifies the parts a unit test can't reach — the real
`NSSystemTimeZoneDidChange` delivery, Core Location, launch reconciliation, and the actual AlarmKit
**ring**. Run it before any travel-affecting release.

## How to read this

- **The unit tests prove the *outcome logic*; this matrix proves the *device integration*.** If a row
  fails on device but its automated pin is green, the defect is in the adapter/wiring, not the policy.
- **Alarm config shorthand.** Travel behavior: **FL** = follow-local, **SF** = stay-fixed, **ASK** =
  ask-on-change. Criticality: **STD** = standard, **CRIT** = critical.
- **Record the outcome.** Each row states the **expected alarm outcome**; tick **Pass** only when the
  device matches it exactly. A divergence on any critical-alarm row is a release blocker.
- **Simulating a zone change.** Manual: *Settings → General → Date & Time → off Set Automatically →
  change Time Zone*. Simulator: *Features → …* or the scheme's Default Location, and *xcrun simctl* for
  the system zone. Automatic: a real cellular network move (a flight, or a border), or launch after a
  change made while the app was closed.

## Universal safety expectations (hold in EVERY row)

- A **critical** alarm is **never silently moved, cancelled, or lost** — a change to it is
  confirmation-gated (#6) and no response leaves it unchanged (#7/#16).
- A movement/zone/region signal **never suppresses** an alarm (#8); background is opportunistic, so the
  alarm rings even if no background run happens (#9).
- **No coordinates** are ever stored or logged; only a coarse movement timestamp (#41).
- An **ambiguous / failed / denied** signal preserves the last-safe schedule (#10).

---

## 1. Manual time-zone change

| # | Setup | Config | Expected alarm outcome | Invariants | Automated pin | Pass |
|---|---|---|---|---|---|---|
| 1.1 | Change device zone Tokyo→New York in Settings | FL / STD | Alarm rings at the **same wall-clock** (e.g. 07:00) in New York | #12 | `TravelPolicyEvaluatorTests`, `TravelBehaviorSchedulingTests` | ▢ |
| 1.2 | Same change | SF / STD | Alarm rings at the **same absolute instant** (07:00 Tokyo = 17:00 prev-day NY) | #12 | `TravelBehaviorSchedulingTests` | ▢ |
| 1.3 | Same change | ASK / STD | A prompt **previews old (Tokyo) vs new (NY) ring times**; choosing follow-local re-anchors, keep-anchor does not | #16 | `TimeZoneChangePromptTests` | ▢ |
| 1.4 | Same change, **ignore** the prompt | ASK / STD | **No response ⇒ the alarm keeps its anchor** (documented default), unchanged | #7/#16 | `TimeZoneChangePromptTests` | ▢ |
| 1.5 | Same change, choose follow-local | ASK / **CRIT** | The change **requires explicit confirmation** before it moves; until confirmed, the alarm is unchanged | #6/#16 | `TimeZoneChangePromptTests` | ▢ |

## 2. Automatic zone change + launch reconciliation

| # | Setup | Config | Expected alarm outcome | Invariants | Automated pin | Pass |
|---|---|---|---|---|---|---|
| 2.1 | Real cellular move across zones (device auto-updates) | FL / STD | The `NSSystemTimeZoneDidChange` path records **previous → current** IANA zone; the alarm behaves as row 1.1 | #11/#12 | `TimeZoneObserverTests` | ▢ |
| 2.2 | Change the zone **while the app is closed**, then launch | any | Launch reconciliation catches the change **once**; no phantom/duplicate change on relaunch | #11 | `TimeZoneObserverTests` | ▢ |
| 2.3 | A repeated / no-op zone notification | any | **No** phantom change, **no** duplicate prompt | #11 | `TimeZoneObserverTests` | ▢ |
| 2.4 | Device set to a fixed-offset / non-geographic zone (e.g. GMT+5) | any | The non-IANA zone is **skipped without a crash**; detection continues | #11 | `TimeZoneObserverTests`, `IANATimeZone` tests | ▢ |

## 3. DST transition during travel

| # | Setup | Config | Expected alarm outcome | Invariants | Automated pin | Pass |
|---|---|---|---|---|---|---|
| 3.1 | Arrive in New York across its spring-forward night; alarm 02:30 | FL / STD | 02:30 doesn't exist → fires at the **gap's end 03:00**, never skipped; the prompt flags it | #12 | `TravelDSTCompositionTests`, `AlarmSchedulingEngineTests` | ▢ |
| 3.2 | Arrive across a fall-back night; alarm 01:30 | FL / STD | 01:30 happens twice → fires **once, at the earlier** instant | #12 | `TravelDSTCompositionTests` | ▢ |
| 3.3 | Alarm anchored to New York, device in DST-free Tokyo, NY spring night | SF / STD | DST is resolved in the **anchor (NY)** → gap-end 03:00; the DST-free device zone doesn't change that | #12 | `TravelDSTCompositionTests` | ▢ |
| 3.4 | 30-minute-DST zone (`Australia/Lord_Howe`) spring night, weekly alarm | FL / STD | Fires at the gap end on the **transition day** — not a week late | #12 | `AlarmSchedulingEngineTests` | ▢ |

## 4. International Date Line travel

| # | Setup | Config | Expected alarm outcome | Invariants | Automated pin | Pass |
|---|---|---|---|---|---|---|
| 4.1 | Cross the IDL onto a **skipped** calendar day; one-time alarm on that day | FL / STD | Fires at the **same wall-clock on the next existing day** — never lost — and the UI shows the **date** | #12 | `TravelDateLineTests`, `AlarmSchedulingDateLineTests` | ▢ |
| 4.2 | Same, alarm anchored to the skipping zone | SF / STD | IDL resolved in the **anchor** → next existing day; follow-local in a normal device zone stays exact | #12 | `TravelDateLineTests` | ▢ |
| 4.3 | Same IDL crossing | ASK / **CRIT** | **Never lost** (a real future instant either way); a shift **confirms** (#6); no response keeps the anchor (#7) | #6/#7 | `TravelDateLineTests` | ▢ |
| 4.4 | Extreme offsets — UTC+14 `Pacific/Kiritimati`, −11 `Pacific/Pago_Pago`, +5:45 `Asia/Kathmandu`, +12:45 `Pacific/Chatham` | any | Ring at the **correct local time**; no unintended duplicate or skipped fire | #12 | `AlarmSchedulingDateLineTests` | ▢ |

## 5. Location denied / disabled (feature works without permission)

| # | Setup | Config | Expected alarm outcome | Invariants | Automated pin | Pass |
|---|---|---|---|---|---|---|
| 5.1 | Location permission **denied**, then a real zone change | any | Travel detection **still works** (degrades to time-zone-only); the alarm behaves as §1 | #10/#41 | `SignificantLocationTests`, `TravelContextTests` | ▢ |
| 5.2 | Location **granted**, corroborated move | ASK / STD | The prompt still previews old/new; corroboration **never re-anchors on its own** (location can't override the system zone) | #16 | `TravelPolicyEvaluatorTests` | ▢ |
| 5.3 | Open the location education + control | — | The copy explains the **approximate purpose + low-power/never-GPS battery** behavior; the toggle **enables/disables** and persists; disabling is available even when denied | #41 | `LocationMonitoringModelTests`, `LocationPrivacyGuardTests` | ▢ |
| 5.4 | Monitor battery/privacy across a travel day | — | **No continuous-GPS drain** (no persistent location arrow); **no coordinates** stored or logged | #41 | `LocationPrivacyGuardTests` | ▢ |

## 6. Stale callbacks / airport & rapid zone changes

| # | Setup | Config | Expected alarm outcome | Invariants | Automated pin | Pass |
|---|---|---|---|---|---|---|
| 6.1 | Airport: the zone **flaps** rapidly (VPN / partial signal) | ASK / STD | **No prompt spam** — a prompt appears only once the zone **settles**; the alarm is untouched while flapping | #16 | `RapidZoneChangeGateTests` | ▢ |
| 6.2 | A **delayed / out-of-order** zone callback arrives after a newer one | any | The **latest reliable** state wins (versioning); the stale callback **does not** win | #10 | `RapidZoneChangeGateTests` | ▢ |
| 6.3 | A zone change lands **within minutes of a ring** | any | The change is **deferred** — the imminent alarm is **not destabilized** and rings as scheduled | #9/#16 | `RapidZoneChangeGateTests` | ▢ |
| 6.4 | A stale travel prompt from an earlier flapping is acted on late | ASK / **CRIT** | Harmless — a critical change still **confirms**; no response keeps the anchor | #6/#7 | `TimeZoneChangePromptTests` | ▢ |

---

## Sign-off

- Tester / device / iOS version: ________________________
- Date: ________________________
- All **critical-alarm** rows (1.5, 4.3, 6.3, 6.4) passed: ▢ — **a fail here blocks release.**
- Deviations recorded in `DECISIONS.md` / a linked issue: ________________________

The deterministic outcomes above are locked by the cited automated tests (`make ci-fast`); this matrix is
the device-integration companion. See also `RELEASE_CHECKLIST.md` (travel & time-zone section) and
`SAFETY_INVARIANTS.md`.
