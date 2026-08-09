# Motion Calibration Study (WG-075)

The wake-challenge motion analyzers (WG-065 device-carried, WG-066 altimeter, WG-069 ten-second
walk, WG-070 cadence anti-shake) ship with **cautious baseline thresholds** (`CalibrationProfile`
`.baseline`). This study tunes them on real hardware and records the decision in the WG-075 ADR.

## Ground rules

- **No participant identifiers.** Recording uses the WG-074 `MotionTraceRecorder` — DEBUG-only,
  consent-gated, and **anonymized** (relative timestamps, no name / device / location / raw axes).
  `CalibrationProfile` stores only tuning parameters. Traces stay **on-device / internal**, never
  distributed (a gait/step series is a behavioral fingerprint).
- **Consent + on-device only.** Every session starts by acknowledging `MotionTraceRecorder.consentWarning`;
  the recorder does not exist in release builds.
- **Safe direction wins ties.** A threshold is chosen to reject every cheat (no false *pass*) even at
  the cost of occasionally rejecting a genuine walk (a false *fail*) — a false fail is covered by the
  always-available accessible alternative (#21), a false pass is not. `WalkRequirements` re-clamps on
  decode, so calibration can make the walk **stricter, never weaker** than the ten-second floor.

## Test matrix

Run each cell with ≥ 3 testers of varied build/gait. For each, record an anonymized trace and note the
analyzer verdict.

| # | Condition | Carry position | Action | Expected verdict |
|---|-----------|----------------|--------|------------------|
| 1 | Still | hand | hold still | walk: not pass · device-motion: stationary |
| 2 | Still | pocket | hold still | stationary |
| 3 | Still | bag | hold still | stationary |
| 4 | Slow gait | hand | slow walk ≥ 10 s | walk: **pass** · cadence: plausibleGait |
| 5 | Slow gait | pocket | slow walk ≥ 10 s | walk: **pass** |
| 6 | Slow gait | bag | slow walk ≥ 10 s (bouncing) | walk: pass (watch false-fail) |
| 7 | Brisk gait | hand | brisk walk ≥ 10 s | walk: **pass** · cadence: plausibleGait |
| 8 | Brisk gait | pocket | brisk walk ≥ 10 s | walk: **pass** |
| 9 | Brisk gait | bag | brisk walk ≥ 10 s | walk: **pass** |
| 10 | Stairs | hand | up/down a flight | altimeter: significantChange (corroborating only) |
| 11 | Pickup only | hand | lift + tilt, no steps | device-motion: pickup · walk: **not pass** |
| 12 | Shake — rhythmic | hand | metronomic ~2/s shake | cadence: **tooRegular** / not pass |
| 13 | Shake — erratic | hand | fast irregular shake | cadence: **tooErratic / implausibleTiming** |
| 14 | Shake — nightstand | device on surface | shake/jostle the phone | device-motion: irregularShaking · not pass |
| 15 | Shake — paced (cheat) | hand | deliberate ~2/s paced shake | **known residual** (WG-070) — must be caught by requiring pedometer + a second signal |

## What to record per cell

- Pedometer step count + reconstructed inter-step intervals (cadence CV, per-step timing band).
- Device-motion: max user-acceleration, max rotation, gravity-angle range + net change.
- Altimeter: net altitude change + rate.
- Movement-episode duration + observation density (mean inter-observation gap).
- The analyzer verdict vs. the expected verdict; flag every mismatch.

## Deciding the thresholds

For each threshold, pick the value that separates the **pass** cells (4–10) from the **not-pass** cells
(1–3, 11–14) across all testers, with margin. Where no single value separates them (e.g. cell 15, the
paced shake), record it as a **residual** requiring a second independent signal — do not loosen a
threshold to force a case. Enter the chosen values into a `CalibrationProfile` and record them, with
the rationale and the residuals, in the **WG-075 ADR** (`docs/DECISIONS.md`). Re-run the matrix against
the tuned profile to confirm no regression before it replaces the baseline.
