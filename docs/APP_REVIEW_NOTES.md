# App Review notes (WG-191)

Notes for the App Store reviewer. Backed by `AppReviewNotesTests`, which checks the required sections are
present and that no capability is claimed that the app does not have.

## Testing alarms

1. **Create an alarm** — tap **+**, pick a time, save. WakeGuard schedules a real system alarm via AlarmKit.
2. **Critical alarm** — toggle *Critical* when creating. A critical alarm rings through silent mode and
   Focus, and **requires explicit confirmation** to cancel or delay.
3. **Wake-up walk challenge** — enable the walk challenge on an alarm. There is an **accessible
   alternative** for users who cannot walk or carry the phone; a failed, denied, or ambiguous challenge
   **keeps the alarm active** with a safe fallback.
4. **Natural-language creation** — on the conversational screen, type e.g. "wake me at 7 tomorrow". A
   **preview** of the parsed schedule is shown; **nothing is scheduled until you confirm**, and a one-tap
   manual editor is always available.

## Testing optional permissions

Motion, Location, Health, Calendar, and Cloud AI are **optional**. The app is fully functional — alarms
ring — with **all of them denied**. Only Alarm and Notifications are needed for alerts.

- Open **Settings → Permissions & privacy** in-app: every capability is listed **separately** with its
  purpose and revocation guidance.
- Grant or deny each in iOS Settings; the app degrades gracefully in every state and never blocks alarms.

## Safety behavior

- The core is **deterministic**; AI is **advisory and permission-gated**. The AI **cannot** call AlarmKit
  or mutate data directly — it only *proposes*. Every mutation passes through a policy engine and is
  audited (AI proposals are attributed distinctly from user actions).
- A movement inference alone **never** suppresses an alarm. A failed/denied/ambiguous challenge keeps the
  alarm active.
- Critical alarms require explicit confirmation to cancel or delay.

## No fake capabilities

Everything shown is real and on-device. AI runs on the device (Apple Foundation Models).
**Cloud AI is off by default** and requires separate, explicit consent. WakeGuard makes **no medical
diagnosis**, includes **no analytics and no tracking**, and ships **no third-party SDKs**.

## Demo

No special demo mode is required — create a real alarm to exercise the full flow. A reviewer/preview build
may seed sample alarms via `ReviewDemoContent`; these are ordinary alarm definitions (real data), **not**
simulated behavior.

## Contact

privacy@wakeguard.app
