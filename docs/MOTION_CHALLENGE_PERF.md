# Motion challenge battery & responsiveness (WG-224)

## Sensors start only when needed

The step sensor is driven by the challenge's `AsyncStream`. It starts when the challenge stream is created
(the user is on the walk-challenge screen) and **stops on stream termination** — `continuation.onTermination
= { _ in updates.stop() }` calls `CMPedometer.stopUpdates()`. So the pedometer runs **only** during an
active challenge, never at launch, in the background, or after the challenge ends. Pinned by
`MotionChallengeSensorTests`.

## No unnecessary high-frequency sampling

The challenge uses **`CMPedometer`** (cumulative step counts, low update rate), **not** raw
`CMMotionManager` accelerometer/device-motion/gyro streams at high Hz. Cumulative step counting is what the
walk challenge needs; it is far cheaper than raw inertial sampling. A regression to a high-frequency API
fails CI (scan).

## Pass latency target

| Metric | Target |
|---|---|
| Step → progress update | ≤ 250 ms |
| Qualifying step → challenge pass | ≤ 500 ms |

Each pedometer reading is processed synchronously by the challenge machine (no batching), so a qualifying
step advances or completes the challenge on the next reading — well within target. Absolute latency is
verified on-device (the pedometer's own cadence is the floor).

## Measurement

On-device: walk the challenge and measure step-to-pass latency; confirm the pedometer stops (no residual
sensing) after pass/cancel via the Energy Log.
