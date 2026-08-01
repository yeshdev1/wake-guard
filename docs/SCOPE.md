# MVP Scope and Terminology (Frozen)

This document freezes the MVP scope and the shared vocabulary for WakeGuard.
It is authoritative for what the MVP includes, what it excludes, and what
ambiguous terms mean. Product detail lives in `PRODUCT_SPEC.md`; safety rules
live in `SAFETY_INVARIANTS.md`. Where those documents and this one appear to
conflict, `SAFETY_INVARIANTS.md` wins, then this document, then
`PRODUCT_SPEC.md`.

Task: WG-001. Related: `docs/PRODUCT_SPEC.md`, `docs/SAFETY_INVARIANTS.md`,
`docs/ARCHITECTURE.md`, `docs/DECISIONS.md`.

## 1. Scope freeze and sign-off

The MVP scope below is **frozen**. Changing it requires an entry in
`docs/DECISIONS.md` (an ADR) and human approval before any code change relies
on the new scope. Adding a capability not listed in §3 is out of scope by
default, not by omission.

| Sign-off              | Name / owner            | Date       | Status              |
|-----------------------|-------------------------|------------|---------------------|
| Engineering (WG-001)  | Claude Code (agent)      | 2026-08-01 | Drafted   |
| Product owner         | yeshwanth devabhaktuni   | 2026-08-01 | Approved  |

Freeze status: **Frozen for MVP — human-approved 2026-08-01.** The repo owner
(product owner) countersigned this scope and terminology freeze in the WG-001
sign-off. Changing §2, §3, or §4 now requires an ADR in `docs/DECISIONS.md` and
human approval (`CLAUDE.md`); WG-002+ may proceed on the stable terminology.

## 2. Glossary (frozen terminology)

These definitions are binding across code, tests, UI copy, and documentation.
The four terms named in WG-001 — **critical alarm, occurrence, local time,
fixed-zone time** — are defined first.

### 2.1 The four named terms

- **Critical alarm** — An alarm the user has explicitly marked as
  safety-important (for example: work start, medication, caregiving, a flight).
  Criticality is a property assigned by the user through the
  `AlarmPolicyEngine`, never inferred or assigned by an AI model
  (`SAFETY_INVARIANTS.md` #31). A critical alarm **cannot be cancelled,
  delayed, suppressed, or weakened without explicit user confirmation**
  (#6); no response to a prompt leaves it unchanged (#7); a movement "appears
  awake" inference alone never modifies it (#8). The precise operational
  criteria and defaults (which categories default to critical, snooze/challenge
  constraints) are deferred to **ADR-007** (indexed in `docs/DECISIONS.md`; not
  yet scheduled to a task); this entry fixes the term and its non-negotiable
  safety semantics. Until ADR-007 defines defaults, criticality is an explicit
  user property; when it is unset or unknown the policy engine must treat the
  alarm conservatively and must never auto-downgrade it to non-critical in order
  to permit a mutation (`SAFETY_INVARIANTS.md` #6, #10).

- **Occurrence** — A single scheduled firing of an alarm at one absolute
  instant, derived from the alarm's `ScheduleRule`. A one-time alarm has exactly
  one occurrence; a repeating alarm has many. Commands that name an occurrence
  ("cancel occurrence", "reschedule occurrence", "snooze") act on that single
  firing and do **not** change the alarm definition or its other occurrences.

- **Local time** (also **follow-local** / **wall-clock**) — A schedule behavior
  in which the alarm fires at the same **wall-clock reading** (for example,
  07:00) in whatever IANA time zone the device is currently set to. Crossing
  time zones changes the absolute instant so the clock face the user set stays
  constant. This is the "wall-clock recurring intent" of `SAFETY_INVARIANTS.md`
  #12.

- **Fixed-zone time** (also **stay-fixed**) — A schedule behavior in which the
  alarm is tied to its **original IANA time zone** and fires at the same
  **absolute instant** regardless of where the device travels; after travel the
  displayed local wall-clock reading may differ. This is the "fixed instant
  intent" of `SAFETY_INVARIANTS.md` #12.

### 2.2 Alarm and scheduling terms

- **Alarm** — A user-defined, persisted definition (label, enabled state,
  schedule rule, travel behavior, criticality, sound, snooze/challenge/pre-alarm
  policies, timestamps, revision). Distinct from an *occurrence* (§2.1).
- **ScheduleRule** — The rule that produces occurrences: a one-time zoned
  date-time or a weekly wall-clock recurrence, carrying the original IANA
  time-zone identifier and the local-vs-fixed behavior.
- **Snooze** — A bounded, policy-governed deferral of the *current occurrence*
  by a fixed interval. Snooze never cancels the alarm; for a **critical alarm** a
  snooze is a *delay* and requires the explicit user confirmation mandated by
  `SAFETY_INVARIANTS.md` #6.
- **Reconciliation** — The launch-time and post-uncertainty process that
  compares persisted (desired) alarms against system (AlarmKit) alarms and
  repairs safe divergences, never silently dropping a scheduled alarm
  (`SAFETY_INVARIANTS.md` #10, `ARCHITECTURE.md` §4 AlarmReconciler).

### 2.3 Wake-verification terms

- **Wake challenge** (a.k.a. **ten-second walk**) — A user-initiated task that
  verifies a sustained walking episode using multiple independent signals
  (steps, elapsed time, cadence plausibility, motion activity, device-carried
  evidence). Shaking alone cannot pass (`SAFETY_INVARIANTS.md` #20). Failure,
  sensor gaps, or ambiguity keep the alarm active (fail-safe, #10) while never
  trapping the user indefinitely — an accessible fallback is always available
  (#21, #22).
- **Accessible alternative challenge** — A non-motion path to satisfy the wake
  challenge, always available for users who cannot walk or carry the phone
  (#22). Not optional; part of MVP.
- **Pre-alarm prompt** (a.k.a. **smart pre-alarm check**) — An actionable
  prompt shown before the alarm when deterministic evidence suggests the user
  may already be awake. It offers keep / turn off today / change time / remind
  later. Keep, turn off today, and remind later affect today's *occurrence* only
  (§2.1), not the alarm definition; **change time** opens an edit proposal (see
  WG-086) that alters the alarm definition only on explicit user save. No
  response makes no change (#7); no action ever silently mutates the alarm, and a
  critical alarm always requires the explicit confirmation of #6.

### 2.4 Time, travel, and DST terms

- **IANA time zone** — A named zone identifier (e.g. `America/New_York`) stored
  with each alarm; numeric UTC offsets alone are never stored
  (`SAFETY_INVARIANTS.md` #11).
- **Travel policy** — Per-alarm behavior on a detected time-zone change: one of
  *follow-local* (§2.1), *stay-fixed* (§2.1), *ask after change*, or an optional
  *region rule* with an explicit safe fallback (`PRODUCT_SPEC.md` §3.4). For a
  **critical alarm**, no travel or location signal may change the schedule
  without explicit user confirmation; location is context only, never sole
  authority (`SAFETY_INVARIANTS.md` #6, #16).
- **Ambiguous local time** — A wall-clock time that occurs twice on a fall-back
  DST day. **Nonexistent local time** — a wall-clock time skipped on a
  spring-forward DST day. Both must be detected (`SAFETY_INVARIANTS.md` #14) and
  resolved through the pure scheduling engine (#13).

### 2.5 Safety, audit, and AI terms

- **AlarmManagerAdapter** — The only component permitted to call AlarmKit, and
  only when invoked by `AlarmCommandProcessor` (`SAFETY_INVARIANTS.md` #1, #2).
  (Naming note: `ARCHITECTURE.md` §4 does not yet list this adapter by name; the
  identifier is reconciled as a documentation follow-up, see `DECISIONS.md`.)
- **AlarmCommandProcessor** — The single serialization boundary that applies an
  authorized command to local state and, through `AlarmManagerAdapter`, to
  AlarmKit via an outbox/reconciliation pattern (`SAFETY_INVARIANTS.md` #2,
  `ARCHITECTURE.md` §4).
- **AlarmPolicyEngine** — The deterministic authority that authorizes or rejects
  every alarm command based on criticality, source, user confirmation, time
  remaining, permissions, and settings. The model never authorizes commands
  (`SAFETY_INVARIANTS.md` #3, #31).
- **AlarmProposal** — A constrained, validated, expiring suggestion produced by
  an AI feature. It is advisory only and is never executable without schema
  validation and policy authorization (`SAFETY_INVARIANTS.md` #4, #5, #26, #27).
- **Audit event** — An append-only record of every alarm mutation (actor,
  command, old/new state, reason, timestamp, correlation ID, outcome)
  (`SAFETY_INVARIANTS.md` #46–#49).
- **"Appears awake" vs "is awake"** — Product language principle: the app states
  inferences as uncertain ("appears awake", "sleep estimate"), never as fact or
  diagnosis (`PRODUCT_SPEC.md` §6).

## 3. In scope (MVP)

Frozen. Detail in `PRODUCT_SPEC.md` §3.

1. **Alarm creation and management** — one-time and weekly repeating alarms;
   label, sound, snooze/criticality/challenge/travel policies; clear next-fire
   date and time zone; persistence–system reconciliation; history and audit.
2. **Ten-second walk challenge** — multi-signal verification; anti-cheat;
   failure keeps the alarm active; **accessible alternative always available**.
3. **Smart pre-alarm check** — deterministic "appears awake" evidence and an
   actionable prompt; no-response makes no change; critical alarms need explicit
   confirmation.
4. **Time-zone and travel behavior** — per-alarm follow-local / stay-fixed / ask
   / region-rule; time-zone change is the primary signal; low-power location is
   context only, never sole authority.
5. **Optional HealthKit circadian intelligence** — permissioned sleep-analysis
   read; transparent consistency / sleep-debt estimates; readiness *explanation*,
   not diagnosis; transparent, non-diagnostic suggestions (bedtime, light
   exposure, caffeine cutoff, alarm adjustments) per `PRODUCT_SPEC.md` §3.5.
6. **Optional calendar-aware planning** — permissioned event read; latest safe
   wake time from prep/travel buffers; recommends, never silently schedules.
7. **Advisory on-device AI** — natural-language setup, planning, explanations,
   journaling; structured, validated, bounded output routed through
   deterministic policy. On-device Foundation Models only for MVP (cloud AI
   processing is out of scope — see §4).
8. **Auditability and history** — every mutation recorded; user-understandable
   history; recovery distinguishable from ordinary edits.

## 4. Out of scope (MVP)

Explicitly excluded. Anything here requires an ADR + human approval to add.
Aligned with `PRODUCT_SPEC.md` §4; the advertising exclusion is broadened to
match `SAFETY_INVARIANTS.md` #40 (adds location and calendar data).

- Medical diagnosis, sleep-disorder detection, or treatment advice.
- Automatic alarm cancellation based only on a movement inference.
- Continuous overnight GPS.
- Real-time Apple Watch sleep-stage smart alarm.
- Emergency-contact escalation.
- Cloud storage of raw HealthKit, motion, location, calendar, or journal data.
- Cloud AI *processing* in the MVP — on-device Foundation Models only; any
  opt-in cloud model provider is deferred pending ADR-004 (`ARCHITECTURE.md` §8,
  `SAFETY_INVARIANTS.md` #34, #35).
- Android.
- Social features.
- Advertising based on health, motion, location, or calendar data.
- Fully autonomous alarm changes (AI acting without policy + user authority).

## 5. Change control

- This document is frozen for the MVP. Any change to the meaning of a §2 glossary
  term, or to §3 or §4, requires an ADR in `docs/DECISIONS.md` and human
  approval; only non-semantic clarifications (spelling, cross-references) may be
  made without an ADR.
- Glossary terms in §2 are the canonical spellings and meanings; code, tests,
  and UI copy should use them consistently.
- No safety invariant may be weakened to accommodate a scope change
  (`CLAUDE.md`, `SAFETY_INVARIANTS.md`).
