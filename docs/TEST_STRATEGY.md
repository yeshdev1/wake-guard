# Test Strategy

## 1. Test pyramid

### Pure unit tests

- schedule occurrence calculations;
- DST/nonexistent/ambiguous times;
- fixed-zone and local-zone policies;
- policy authorization;
- movement episode aggregation;
- wake challenge state machine;
- readiness formulas;
- AI schema validation;
- redaction;
- migration transforms.

### Adapter contract tests

- AlarmKit adapter through a test seam where possible;
- Core Motion normalization;
- HealthKit query mapping;
- EventKit redaction and event mapping;
- Core Location timestamp filtering;
- notification action routing;
- model provider structured output.

### Integration tests

- create/edit/disable/reconcile alarm;
- pre-alarm prompt action to command processor;
- time-zone change to proposed schedule;
- challenge pass to alarm stop command;
- AI proposal to policy rejection/approval;
- persistence migration and recovery.

### UI tests

- onboarding and permission explanations;
- alarm creation and edit;
- ringing/challenge progress;
- pre-alarm prompt deep links;
- critical confirmation;
- travel prompt;
- privacy controls;
- Dynamic Type and VoiceOver landmarks.

### Real-device tests

Required because Simulator cannot faithfully validate the full alarm, motion, notification, lock-screen, location, and HealthKit behavior.

## 2. Required deterministic test utilities

- `TestClock`
- `TestTimeZoneProvider`
- `DeterministicIDGenerator`
- `FakeAlarmManager`
- `FakePedometer`
- `FakeMotionActivitySource`
- `MotionTracePlayer`
- `FakeLocationProvider`
- `FakeHealthStore`
- `FakeEventStore`
- `FakeNotificationCenter`
- `FakeLanguageModelProvider`
- `InMemoryAlarmRepository`
- `FaultInjectingRepository`

## 3. Time-zone matrix

At minimum:

- Asia/Kolkata, no DST;
- America/New_York, DST;
- Europe/London, DST;
- Australia/Lord_Howe, half-hour DST behavior;
- Pacific/Auckland;
- Pacific/Kiritimati;
- Pacific/Pago_Pago;
- zones with 30- and 45-minute offsets;
- transitions across the International Date Line.

Test:

- spring-forward nonexistent local time;
- fall-back duplicated local time;
- time-zone change before and after alarm;
- recurrence across DST;
- device time changed manually;
- automatic time-zone disabled;
- stale cached location;
- repeated time-zone notifications.

## 4. Motion trace library

Record or synthetically generate labeled traces:

- phone stationary;
- person rolls in bed;
- phone picked up;
- phone shaken while seated;
- eight-second walk;
- valid ten-second walk;
- slow walk;
- brisk walk;
- limp/irregular gait;
- stairs;
- phone in hand;
- phone in pocket;
- phone in bag;
- wheelchair or non-walking accessible flow;
- interrupted permissions;
- app background/foreground during challenge.

Store no real participant identifiers.

## 5. Fault injection

Inject:

- AlarmKit schedule failure;
- uncertain timeout after scheduling;
- persistence write failure;
- corrupted record;
- duplicated callback;
- out-of-order callback;
- cancelled async task;
- BG task expiration;
- notification authorization revoked;
- motion authorization revoked;
- HealthKit unavailable;
- model unavailable;
- malformed model output;
- location callback with stale timestamp;
- time-zone change during edit;
- device restart between outbox write and external schedule.

## 6. Release quality thresholds

Set exact values after baseline measurements. Initial gates:

- zero P0/P1 known defects;
- no flaky safety tests across 100 repeated runs;
- schedule property tests across at least 10,000 generated cases;
- no sensitive data in captured logs;
- no accessibility blocker;
- no crash in repeated alarm/challenge loops;
- acceptable battery usage in overnight and travel-mode trials;
- cold-launch reconciliation completes within the agreed budget;
- all critical user flows pass on the minimum and current supported iPhone classes.

## 7. Manual test evidence

Each release candidate should store:

- device model;
- OS version;
- settings and permissions;
- alarm configuration;
- expected result;
- actual result;
- screen recording or screenshot where appropriate;
- logs with sensitive fields redacted;
- tester and date.
