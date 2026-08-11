# Epoch 2 (WG-241): Functional bug hunt

An independent reviewer adversarially exercised the core flows (alarm CRUD, list, challenge, history,
conversational creation, readiness, consent, diagnostics) with normal and abnormal inputs. The codebase is
exceptionally well-tested; **no P0/P1** was found. Two genuine P2 bugs were found, **fixed**, and pinned
with regression tests.

| Severity | Bug | Repro | Fix | Regression test |
|---|---|---|---|---|
| P2 | A can't-ring **critical** alarm showed a reassuring "Critical" status, hiding that it won't fire | enabled + `.critical` + one-time date in the past ⇒ no occurrence ⇒ status "Critical" instead of "Needs attention" | `AlarmListViewModel.status(for:)` now checks "has an occurrence" **before** criticality — an enabled alarm with nothing upcoming is `.attention` even if critical | `AlarmListViewModelTests.testEnabledCriticalAlarmWithNoOccurrenceStillSurfacesAttention` |
| P2 | `ConversationalAlarmViewModel.confirm()` could commit **twice** on a concurrent double-tap | fire `confirm()` twice before the first `await commit` resolves ⇒ both pass the guard ⇒ duplicate alarm | clear `pending` **before** the `await`, so a second concurrent `confirm()` fails the guard (commit at most once) | `ConversationalConfirmConcurrencyTests.testConcurrentConfirmCommitsAtMostOnce` |

Flows verified correct + well-tested (no action): create/edit alarm (empty weekdays, past one-time,
DST/travel round-trip, criticality, lapsed-since-preview re-validation), list (`.failed` never collapses to
`.empty`, load-generation guard, optimistic-toggle restore), challenge machines (alarm stays active for
every non-`.passed` outcome, inflation-proof progress, debounced taps), history (fail-closed decode,
redaction), readiness (degrades to no-factor), pre-alarm chain (prompt-only, critical-gated), and every
read/advisory view-model (no alarm authority).

**No P0/P1 open.** Both P2s fixed in this epoch.
