# Location & background scheduling (WG-225)

## No continuous GPS

Travel/time-zone detection uses **`startMonitoringSignificantLocationChanges`** only — cell/Wi-Fi based,
never `startUpdatingLocation`. Pinned by `BackgroundSchedulingTests` (+ WG-223). The radio is never held
awake.

## Background requests are not spammed

`PreAlarmBackgroundRunner` bounds the next-opportunity request: `nextRequestTime(after:)` is always
`now + minimumReschedule`, and `Config` clamps `minimumReschedule` to **≥ 60 s** (default **900 s** / 15
min; a non-finite or too-small value falls back to 900). So background submissions can't tight-loop, no
matter how often the app is woken. Pinned by a test.

## Travel functionality survives throttling

- **Significant-location wakes the app independently of BG-task budget.** Even if `BGTaskScheduler` requests
  are throttled or never run, a significant-location change still delivers, so time-zone travel detection
  keeps working.
- **The runner reschedules the next opportunity *first*** (before doing any work), so an expired or killed
  run still leaves the next opportunity queued.
- **Background is opportunistic and holds no alarm authority.** The runner only executes advisory `work`; it
  never schedules, cancels, or mutates an alarm, and a critical alarm never depends on a BG run (#10). A
  scan pins the runner references no alarm-mutation path.
