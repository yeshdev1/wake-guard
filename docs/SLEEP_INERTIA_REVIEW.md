# Sleep-inertia usability review (WG-208)

A just-woken user is groggy: they misread, mis-tap, and can't handle choice. The ringing/challenge screens
are designed and reviewed against that. Enforced by `SleepInertiaTests` and `SleepInertiaGuidelines`.

## Findings

- **Minimal choices.** The challenge screen shows the challenge itself plus at most the accessible
  alternative — ≤ `maxWakeScreenActions` (3) interactive controls. No settings, no menus.
- **Short, concrete copy.** On-screen prompts are ≤ `maxWakeCopyCharacters` (48) characters ("Press and
  hold", "Walk to dismiss") — an instruction, not a paragraph.
- **Accidental destructive taps reduced.** The wake/challenge screens expose **no destructive action** —
  you cannot cancel, snooze, or delete an alarm with a stray tap; the alarm stops only by **completing the
  challenge** (or its accessible alternative). Destructive changes to alarms live elsewhere and are
  confirmation-gated (#6).

## Guidelines (for future wake screens)

- Keep to one primary action; add the accessible alternative only.
- Copy is an imperative instruction, short enough to read half-asleep.
- Never place a destructive or irreversible control on a ringing/challenge screen.
