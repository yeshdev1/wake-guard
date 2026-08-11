# Epoch 4 (WG-243): Motion spoofing & false-inference red team

The motion red-team confirmed the Epoch-1 P1: the anti-shake discriminators (`CadenceRegularity`,
`WalkVerifier`, `DeviceMotionEvidence`) were complete + unit-tested but invoked by **no runtime pass path** —
`WakeChallengeMachine.apply(.observedProgress)` passed on cumulative **step count alone**, so a shake that
yields pedometer steps could stop the alarm (#20), with no end-to-end "shake can't pass" test.

## Fixed (#19/#20 now enforced at the trust boundary)

The pass gate is now inside the deterministic state machine — the single chokepoint, so no future caller can
bypass it:

- `WakeChallengeEvent.observedProgress` carries a `MovementCorroboration` (`corroborated` / `contradicted` /
  `unavailable`), fused from the cadence verdict by `ChallengeObservationReducer` (the missing feeder).
- **A pass requires `.corroborated`** (plausible gait). `.contradicted` (erratic/metronomic shake or replay)
  **resets** banked progress — defeating a "shake to fill the bar, then one clean step" splice. `.unavailable`
  (cadence can't be judged yet) **accumulates** the count but can't pass on it alone, so a fast shake in the
  low-data window is held, not admitted.
- A genuine walk of the required length generates enough step intervals to be corroborated, so real walkers
  aren't blocked; the sensor-limited edge falls back to the always-available **accessible alternative** (#22),
  so the user is never trapped (#21). The accessible pass path is untouched.

## Attack vectors

| Attack | Before | After |
|---|---|---|
| Sustained shake producing steps | **passed** (count-only) | never passes (not `.corroborated`) |
| In-bed micro-movement producing steps | passed | held/reset unless a real gait is corroborated |
| Delayed / batched samples | count safe, corroboration bypassed | cadence reconstructed from sensor timestamps; a batch can't fake even cadence |
| Replayed / duplicate samples | count safe, verdict unused | `.tooRegular`/duplicate-drop → not corroborated |
| Phone handoff | not addressed | **residual** (no continuity signal) — recorded, not silently ignored |

## Regression tests

`ChallengeAntiShakeTests` (end-to-end, via the reducer): a bursty-shake stream never reaches `.passed` even
with ≥ required steps; a real-gait stream passes; a sensor-limited stream needs corroboration (doesn't pass on
steps alone); a contradiction zeroes progress so a shake-then-clean-step splice can't pass. The machine-level
tests were migrated to the corroborated event signature.

## Threshold evidence + residuals

Cadence/gait thresholds (`CadenceThresholds.default`, `WalkRequirements`) are cautious and documented as
requiring WG-075 on-device calibration; the fix uses them unchanged (miscalibration biases toward *not*
corroborating = fail-safe). **Residual:** phone-handoff has no continuity/identity signal and is out of scope
for the anti-shake defenses — recorded here as a known limitation for a future backlog item, not an unstated
gap.
