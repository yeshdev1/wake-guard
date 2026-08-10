# Calendar Data-Minimization & Redaction Plan (WG-140)

WakeGuard's calendar-aware planning reads a **minimal** slice of EventKit, keeps event **titles on the
device only**, and hands a model **only a redacted, text-free summary**. This is the single enforceable
source of truth for what is retained, why, where it may go, and how it is redacted. It is backed by typed
code — `CalendarDataMinimizationPlan`, `CalendarEvent`, and `RedactedEventSummary`
(`Sources/CalendarDomain/`) — so several guarantees are *structural*, not just prose. Invariants:
`SAFETY_INVARIANTS.md` #28 (calendar titles are untrusted prompt content), #35 (no full calendar text to a
cloud model by default), #40, #41; `PRODUCT_SPEC.md` §3.6 / non-goals.

## Retained fields

| Field | Kept for | Sensitivity |
|---|---|---|
| `start` | Compute the latest safe wake time before the event (WG-145). | **model-safe** |
| `end` | Estimate how long the event runs. | **model-safe** |
| `isAllDay` | Skip all-day events, which don't drive a wake time. | **model-safe** |
| `hasLocation` | Add a travel buffer when an event has a location — the **boolean only**, never coordinates or an address (#41). | **model-safe** |
| `title` | Show the event so the user can confirm which one matters (WG-143). **Stays on device; never modelled.** | **local-only** |

That is the **entire** set. **Notes, attendees, URLs, and the location string/coordinates are not
retained at all.**

## Titles/notes remain local

- The `title` is retained only to display the event to the user (to confirm the important one, WG-143). It
  is **untrusted content** (#28) and **local-only** — it never reaches a model or leaves the device.
- **Notes are not retained**, so they trivially never leave EventKit.

## Model-facing summaries are redacted

The **only** projection of calendar data that a model (E09 Tomorrow Agent) or any off-device path ever
sees is `RedactedEventSummary` = `{start, end, isAllDay, hasLocation, isConfirmedImportant}`. It carries
**no free text** — no title, no notes, no location string. So:

- A **malicious event title** (prompt injection, #28) cannot reach the model, because titles are never
  summarized.
- **No full calendar text** is ever sent to a cloud model by default (#35).

## Structural guarantees (enforced by the type system)

- **A title can't leak to a model.** `RedactedEventSummary` has no title/notes/location field — the
  redaction is a projection to the plan's `modelSafe` fields only. A test encodes a summary of an event
  with a sensitive title and confirms none of it survives (`testRedactedSummaryNeverContainsTheTitleText`).
- **`hasLocation` is coarse.** It is a `Bool`; the coordinates/address are never modelled (#41).
- **Every retained field is justified.** Each carries a `purpose`; the EventKit adapter (WG-142) maps only
  `CalendarDataMinimizationPlan.retainedFields`.
- **Domain purity is lint-enforced.** `CalendarDomain` is added to the `domain_no_apple_frameworks` rule,
  so the redaction/plan can never import EventKit — the mapping lives in the WG-142 adapter.

## Change process

Retaining a new field is a deliberate change here (add a `CalendarFieldRule` with a purpose + sensitivity);
a new `modelSafe` field also requires a review of what it could leak. Never read a field ad hoc at a call
site. See also `THREAT_MODEL.md` (privacy leakage) and `RELEASE_CHECKLIST.md`.
