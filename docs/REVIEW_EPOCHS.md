# Adversarial Review and Stabilization Epochs

Do not combine these into one vague “QA pass.” Each epoch has a different reviewer mindset and must produce a written report under `docs/reviews/`.

## Review protocol used by every epoch

1. Freeze the build and record commit SHA, device/OS, feature flags, and permissions.
2. Assign a reviewer or Claude subagent that did not implement the feature.
3. Read the safety invariants before testing.
4. Generate attacks and edge cases before reading existing tests.
5. Execute attacks; capture reproduction evidence.
6. Classify findings:
   - P0: alarm may silently fail, suppress, materially misfire, leak sensitive data, or trap user.
   - P1: major core-flow failure, destructive mutation, severe accessibility issue.
   - P2: meaningful defect with workaround.
   - P3: minor functional or aesthetic defect.
7. For every P0–P2:
   - add a failing regression test where technically possible;
   - fix root cause rather than symptom;
   - rerun the epoch's relevant matrix;
   - ask an independent reviewer to verify.
8. Update `CLAUDE.md` when the same class of mistake could recur.
9. Do not accept “cannot reproduce” without added observability or a bounded investigation.
10. Release only after final regression is performed on the exact candidate.

## Epoch A: Architecture and invariant mapping

Deliverable: table mapping all safety invariants to implementation location, tests, and owner.

Attack questions:

- Can any path call AlarmKit without policy authorization?
- Can an AI proposal become executable through decoding side effects?
- Can persistence and AlarmKit diverge without eventual reconciliation?
- Does cancellation of an async task create an unknown external state?
- Can a critical alarm be changed through notification action without confirmation?

## Epoch B: Functional bug hunt

Test ordinary user behavior plus:

- duplicate taps;
- stale screens;
- edit while alarm fires;
- delete while notification action arrives;
- enable/disable races;
- rapid create/delete;
- app killed during save;
- storage full;
- corrupted state;
- repeated callbacks.

## Epoch C: Clock, recurrence, DST, and travel

Run the complete time-zone matrix. Focus on:

- nonexistent local times;
- duplicate local times;
- weekly recurrence around DST;
- automatic time-zone on/off;
- manual clock changes;
- date-line crossing;
- half-hour and 45-minute zones;
- old travel prompts opened after another zone change;
- an alarm less than five minutes away during a zone change.

## Epoch D: Motion and awake-inference attacks

Attempt:

- shaking in bed;
- swinging phone;
- tapping phone against mattress;
- another person carrying phone;
- phone left on moving vehicle;
- brief bathroom trip and return to sleep;
- slow gait;
- phone in loose bag;
- delayed/replayed samples;
- permission revoked mid-challenge;
- phone lock/unlock mid-challenge;
- background/foreground transitions.

Optimize for low false positives. Never remove the accessible fallback.

## Epoch E: Background and lifecycle chaos

Test:

- app force quit;
- device reboot;
- low power mode;
- background app refresh disabled;
- BG task expiration;
- notification permissions revoked;
- motion/location/health/calendar permission revoked;
- OS memory pressure;
- network unavailable;
- model unavailable;
- update installed with alarms scheduled.

The expected default is preservation of the system alarm.

## Epoch F: AI adversarial review

Corpus includes:

- ambiguous relative dates;
- conflicting instructions;
- hidden instructions inside calendar titles;
- prompt injection inside journal text;
- requests to disable all alarms without confirmation;
- malformed time zones;
- fabricated medical claims;
- coercive or shame-based copy;
- overly confident explanations;
- model refusal;
- partial structured output;
- repeated tool/proposal attempts.

Verify that the model cannot access AlarmKit, persistence, or arbitrary tools.

## Epoch G: Privacy and security

Trace every data category from source to memory, disk, logs, analytics, model prompts, export, and deletion.

Verify:

- no health/motion/location/calendar data used for ads;
- third-party AI sharing has explicit consent;
- crash reports are redacted;
- exported data is intentional;
- deletion works;
- permission revocation works;
- privacy label matches behavior;
- no secrets in repository or app bundle.

## Epoch H: Accessibility

Test VoiceOver, Dynamic Type, Reduce Motion, increased contrast, dark mode, 12/24-hour formatting, RTL, and non-walking challenge.

A user must understand:

- whether the alarm is still scheduled;
- what action will change it;
- whether a challenge passed;
- how to escape an unavailable sensor flow.

## Epoch I: Aesthetic and interaction polish

This epoch is specifically for nonfunctional quality:

- alignment, spacing, typography, hierarchy;
- icon consistency;
- touch target size;
- empty/loading/error/success states;
- animation timing;
- haptic appropriateness;
- copy consistency;
- sleep-inertia cognitive load;
- dark-mode surfaces;
- visual distinction of critical alarms;
- notification-to-app continuity;
- screenshot-level regressions.

Do not close aesthetic findings by saying “subjective.” Compare against an approved design rubric and baseline screenshots.

## Epoch J: Performance and battery

Measure, do not guess:

- cold launch;
- alarm list load;
- reconciliation;
- challenge start latency;
- challenge pass latency;
- overnight idle drain;
- travel monitoring drain;
- memory growth over repeated challenges;
- persistence growth;
- model latency and fallback.

## Epoch K: App Store preflight

Review:

- minimum functionality and product uniqueness;
- permission purpose strings;
- HealthKit and sensitive-data rules;
- third-party AI disclosure and consent;
- privacy policy and nutrition label;
- notifications relevance;
- no medical diagnosis claims;
- reviewer instructions;
- entitlements;
- subscriptions and restore flow if monetized.

## Epoch L: Release-candidate regression

After all fixes:

- rerun the full automated suite;
- rerun all P0/P1 reproductions;
- rerun critical real-device scripts;
- rerun privacy log scanner;
- rerun accessibility smoke tests;
- verify build has no debug menus or test data;
- freeze candidate and record checksum/build number.
