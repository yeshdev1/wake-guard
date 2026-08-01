# Product Specification

## 1. Product statement

WakeGuard is a dependable iPhone alarm that helps a person become meaningfully awake rather than merely tapping dismiss. It can require a verified ten-second walk, detect likely early waking and ask whether to keep or amend the alarm, preserve explicit behavior across time-zone changes, and provide privacy-conscious health and schedule intelligence.

## 2. Target user

People who:

- repeatedly snooze or dismiss alarms while half asleep;
- travel across time zones;
- want the alarm to adapt without making unsafe assumptions;
- want sleep and morning guidance without surrendering control of critical alarms;
- value privacy and on-device processing.

## 3. MVP capabilities

### 3.1 Alarm creation and management

- One-time and weekly repeating alarms.
- Label, sound, snooze policy, criticality, challenge policy, travel policy.
- Clear display of next fire date and associated time zone.
- Reconciliation between app persistence and system alarms.
- Alarm history and change audit.

### 3.2 Ten-second walk challenge

- User explicitly begins the wake challenge from the alarm action.
- The app verifies a sustained walking episode using step count, elapsed time, cadence plausibility, motion activity, and device-carried evidence.
- Default target: configurable 10 seconds and a sensible minimum step range.
- Shaking or rapid irregular phone movement should not pass.
- Failure keeps the alarm active.
- Accessible alternative challenge is always available.

### 3.3 Smart pre-alarm check

- Evaluate recent historical movement before the alarm when the app receives an appropriate execution opportunity.
- If likely awake, show an actionable prompt:
  - Keep original alarm
  - Turn off today
  - Change time
  - Remind later
- Prompt copy must state: unless amended, the alarm will ring at its set time.
- No response causes no change.
- Critical alarms require explicit confirmation and cannot be silently modified.

### 3.4 Travel and time-zone behavior

Each alarm has one of:

- Follow local wall-clock time.
- Stay tied to its original IANA time zone.
- Ask after a detected time-zone change.
- Optional region rule for enable/disable, with an explicit safe fallback.

System time-zone change is the primary signal. Low-power location may provide context, never sole authority.

### 3.5 Health and circadian intelligence

Optional, permissioned features:

- Read recent sleep analysis from HealthKit.
- Estimate sleep consistency and simple sleep debt using transparent formulas.
- Produce a readiness explanation, not a diagnosis.
- Suggest bedtime, light exposure, caffeine cutoff, and alarm adjustments.
- Make clear which inputs were available and which were missing.

### 3.6 Calendar-aware planning

Optional, permissioned features:

- Read upcoming events only after full calendar permission.
- Identify a user-confirmed important event.
- Calculate latest safe wake time from preparation and travel buffers.
- Recommend changes; do not silently schedule them.

### 3.7 AI features

- Natural-language alarm setup.
- Tomorrow planning.
- Explain why an alarm or bedtime is recommended.
- Structure a conversational sleep journal.
- Personalize challenge suggestions.
- Interpret user preferences into explicit policies.

AI output is advisory. Structured output is validated, bounded, and passed through deterministic policy.

## 4. Out of scope for MVP

- Medical diagnosis, sleep-disorder detection, or treatment advice.
- Automatic cancellation based only on movement.
- Continuous overnight GPS.
- Real-time Apple Watch sleep-stage smart alarm.
- Emergency-contact escalation.
- Cloud storage of raw HealthKit, motion, location, calendar, or journal data.
- Android.
- Social features.
- Ads based on health or motion data.
- Fully autonomous alarm changes.

## 5. Success metrics

Reliability and safety:

- Zero known silent alarm suppressions.
- 100% of alarm mutations represented in audit history.
- Alarm reconciliation succeeds after simulated divergence.
- Critical alarms never auto-delay or auto-cancel.

Wake effectiveness:

- Challenge pass followed by sustained activity after 5 and 15 minutes.
- Reduction in repeated snoozes.
- User-reported wake quality.

Product:

- Permission funnel completion by feature, not all at onboarding.
- Percentage of suggested alarm changes accepted.
- Pre-alarm prompt false-positive and false-negative feedback.
- Travel prompt usefulness.

Privacy and quality:

- No sensitive payloads in analytics or crash logs.
- Accessibility audit passes.
- Battery impact remains within an agreed real-device budget.

## 6. Product language principles

- Say “appears awake” rather than “is awake.”
- Say “sleep estimate” rather than “diagnosis.”
- State uncertainty.
- State what happens by default.
- Make the safe state explicit: “Your 7:00 AM alarm is still scheduled.”
- Avoid guilt, shame, or competitive sleep scores.
