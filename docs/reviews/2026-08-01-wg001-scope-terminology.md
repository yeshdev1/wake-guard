# Adversarial review — WG-001 scope & terminology freeze

- **Date:** 2026-08-01
- **Task under review:** WG-001 (Freeze MVP scope and terminology)
- **Artifacts:** `docs/SCOPE.md`, `docs/DECISIONS.md` (assumptions log),
  `docs/IMPLEMENTATION_STATUS.md`
- **Commit reviewed:** `9ad87c8` (files as committed to `main`)
- **Method:** multi-agent, loop-until-dry. 3 rounds × 6 independent adversarial
  finder lenses (safety-conflict, internal-consistency, correctness-vs-source,
  completeness, exploitability red-team, quality/clarity); every fresh finding
  cross-examined by 3 independent skeptics with a majority-vote gate; deduped
  across rounds. 134 agents total.
- **Raw findings:** 38 → **confirmed:** 13 → **unique issues:** 7
  (findings 4/5/8/11 were the same `AlarmProposal` miscitation).

## Verdict

**Sound; no safety-invariant weakening.** 0 Blocker, 0 High. Every safety
guarantee verified correct, and two definitions are intentionally *stricter*
than source (#6 adds "suppressed"; #31 bans AI inference of criticality) — safe
direction. Seven documentation-accuracy defects (Medium/Low) were found and
**all fixed in the same pass**. None affected runtime or blocked WG-002.

## Findings and resolution

| # | Sev | Location | Problem | Resolution |
|---|-----|----------|---------|------------|
| M1 | Medium | `SCOPE.md` §3 item 5 | Frozen in-scope dropped the circadian *suggestions* capability (bedtime/light/caffeine/alarm adjustments) present in `PRODUCT_SPEC.md` §3.5 — a silent narrowing vs the source the doc claims to summarize. | **Fixed** — restored the capability with a `PRODUCT_SPEC.md` §3.5 reference. |
| M2 | Medium | `SCOPE.md` §2.3 | "Sensor gaps … keep the alarm active (#21)" — #21 is the *anti-trap* rule (its intent is the opposite: never trap the user). Correct fail-safe basis is #10. | **Fixed** — now cites #10 (fail-safe) for "keep active" and #21/#22 for the never-trap + accessible-fallback guarantee. |
| L1 | Low | `SCOPE.md` §2.5 | `AlarmProposal` cited #11 (IANA time-zone storage) for schema validation/authorization — unrelated invariant. | **Fixed** — now cites #4, #5, #26, #27. |
| L2 | Low | `SCOPE.md` §2.4 | DST entry cited only #14 for a two-part claim; "resolved by the pure scheduling engine" is #13. | **Fixed** — cites #14 (detect) and #13 (resolve). |
| L3 | Low | `SCOPE.md` §2.1, `DECISIONS.md`, `IMPLEMENTATION_STATUS.md` | Operational "critical alarm" definition deferred to "ADR-007 in WG-002", but WG-002's acceptance criteria cover only ADR-001/002/003/004 — a dangling deferral target. | **Fixed** in all three files — ADR-007 now labelled "indexed in `DECISIONS.md`; not yet scheduled to a task." |
| L4 | Low | `SCOPE.md` §2.3 | Pre-alarm "each action affects today's occurrence only" overreaches for **change time**, which (WG-086) opens an edit proposal that can alter the alarm definition on save. | **Fixed** — scoped the claim to keep/turn-off-today/remind-later; change-time described separately. Safety guarantees (#6/#7) retained. |
| L5 | Low | `SCOPE.md` §1/§5 | Doc calls §2 "frozen/binding" but every ADR-gate clause enumerated only §3/§4; whether redefining a term needs an ADR was ambiguous. | **Fixed** — change-control now gates "§2, §3, or §4"; §5 gates semantic changes to glossary terms while allowing non-semantic clarifications. |
| L6 | Low | `IMPLEMENTATION_STATUS.md` | Evidence claimed "16 supporting terms"; §2 actually defines 14 bulleted supporting terms. | **Fixed** — replaced the brittle count with a description of the term groups. |
| N1 | Nit | `SCOPE.md` §4 | "Mirrors `PRODUCT_SPEC.md` §4" overstated equivalence — the advertising exclusion is broadened (adds location/calendar) to match #40. | **Fixed** — header now says "Aligned with … broadened to match #40"; deviation recorded in `DECISIONS.md`. |

Also addressed (open-question, not a defect):

- **Cloud-AI MVP status undefined** — §3 said "on-device AI" but §4 had no
  cloud-AI-*processing* exclusion while ADR-004 is open. **Fixed** — added a §4
  bullet deferring cloud AI processing pending ADR-004 (#34/#35), and a note in
  §3 item 7.

## What stayed strong (verified correct/safe)

- No safety invariant is weakened anywhere; `SAFETY_INVARIANTS.md` precedence
  holds. Every confirmed defect is docs-accuracy, not behavior.
- Critical-alarm semantics correctly pinned to #6/#7/#8/#31 with the applied
  fail-safe default (never auto-downgrade unset/unknown criticality, #6/#10).
- All out-of-scope broadenings are in the *safe* (stricter) direction.
- Anti-cheat (#20), accessible alternative (#22), local/fixed-zone (#12),
  snooze-as-delay (#6), reconciliation (#10), IANA storage (#11 at its correct
  site), and the AI authorization guarantee (#4/#5) are cited correctly.

## Completeness-critic gaps (and how handled)

- **Evidence claims not originally verified** → the false "16 terms" count is
  now corrected (L6).
- **Stricter-than-source strengthening undocumented** → recorded as an
  intentional, no-ADR-required deviation in `DECISIONS.md`.
- **Missing `docs/reviews/` artifact** (this file) → created, satisfying the
  `REVIEW_EPOCHS.md` protocol.
- **`AlarmManagerAdapter` named in `SAFETY_INVARIANTS.md` #1–#2 but absent from
  `ARCHITECTURE.md` §4** → added `AlarmManagerAdapter`/`AlarmCommandProcessor`
  to `SCOPE.md` §2.5; reconciling the name into `ARCHITECTURE.md` is logged as a
  follow-up in `DECISIONS.md`.

## Remaining follow-ups (not WG-001 scope)

1. Reconcile `AlarmManagerAdapter` naming into `ARCHITECTURE.md` §4 (WG-002 or
   WG-024/027/028).
2. Schedule ADR-007 (critical-alarm operational defaults) to a task.
3. Consider adding `SCOPE.md` to the `CLAUDE.md` always-read list.
