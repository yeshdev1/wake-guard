# 100-cycle alarm/challenge soak (WG-228)

## What is exercised

`SoakTests` runs the wake-challenge lifecycle **100 times** in a row (representing 100 alarm rings /
challenge attempts) and asserts each cycle behaves identically to the first.

## Results

- **No crash, leak, or stale state.** Every one of the 100 cycles starts from `.idle` and passes cleanly;
  no state carries over between cycles (the challenge machine is a pure value type, so a completed cycle
  cannot leave a stale reference or half-finished phase behind).
- **Duplicate callbacks do not accumulate.** A held or auto-repeating touch delivers many tap callbacks at
  (nearly) the same instant; the debounce accepts **exactly one**, so duplicates can neither over-count the
  sequence nor pass the challenge by spamming.
- **No accumulation over cycles.** Because each ring uses a fresh machine and the pedometer stream stops on
  termination (WG-224), repeated rings don't accumulate observers, timers, or memory.

## On-device soak

The CI soak covers the deterministic state machine. The full-device soak (100 real alarm rings with the
pedometer and notifications) is run on the device matrix and checked for memory growth and duplicate
notification/challenge callbacks via Instruments (Leaks + Allocations).
