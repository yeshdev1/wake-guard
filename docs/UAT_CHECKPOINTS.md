# UAT Checkpoints

**Purpose.** Verify incrementally at epoch boundaries so on-device / user-acceptance testing does
not pile up at release. Each checkpoint is a small, focused device pass run **as soon as its
enabling epoch lands** — most of the individual items already live in `RELEASE_CHECKLIST.md` and
`DEVICE_SMOKE_TEST.md`; this file says *when* to run them and which ones **gate** further work.

**How to use.** When an epoch's tasks reach Complete in `docs/IMPLEMENTATION_STATUS.md`, run that
checkpoint on a real device, capture evidence (screenshot/recording), and file follow-ups for any
failure. A ★ **safety gate** must pass before the epochs that depend on it are trusted — do not
defer a gate to the end.

| CP | Run after | Focus | Gate |
|----|-----------|-------|------|
| **A — Core UX** | E03 ✅ (now) | Create / edit / delete / all config sections / history on device; VoiceOver, Dynamic Type, dark mode, 12/24h. Simulator UI suite (`make test-ui`) already green. *Alarms don't ring yet — that's CP-B.* | |
| **B — Alarms actually ring** | AlarmKit integration (real `SystemAlarmManagerAdapter` + auth UI + scheme registration) | `DEVICE_SMOKE_TEST.md` SMK-01–15, especially **SMK-04/08/09**: rings through silent / Focus / DND, after force-quit, after reboot; lock-screen actions; deep-link delivery once `wakeguard://` is registered. | ★ **This makes every alarm-safety claim real.** Block E05+ device trust on it. |
| **C — Walk challenge** | E04 | `motion-red-team` device pass: false-pass (shaking / rhythmic tap), false-fail (a legitimate walk), the accessible alternative, phone-carry disclosure, 10-second timing. | ★ wake integrity |
| **D — Pre-alarm** | E05 | Pre-alarm prompt: no response ⇒ alarm unchanged (#7); a critical alarm needs confirmation (#6); awake-inference false-positive / false-negative feel; opportunistic (no reliance on a background run). | |
| **E — Travel / time zone** | E06 | A real time-zone change routes through the choke point; a "keep home-zone" / critical alarm is **never silently shifted** (#16); ask-on-change prompts; **no continuous GPS** (verify with a battery/location trace). | ★ #16 |
| **F — Health & Calendar** | E07 / E08 | Permission requested **in context** with specific purpose copy; denied state degrades safely; data minimization; **no health samples / calendar titles in logs or audit** (#41); HealthKit sleep is not a real-time trigger. | |
| **G — On-device AI** | E09 | AI is **advisory only** — cannot call AlarmKit or mutate persistence; output decoded into constrained types (#4/#5/#27); cannot assign criticality (#31) or suppress a critical alarm; **no sensitive data in prompts** (#41); deterministic fallback when AI is unavailable. | ★ **AI safety boundary.** |
| **H — Privacy & Accessibility** | E10 / E11 | Full privacy audit (data flows, retention, on-device processing, no hidden analytics); full accessibility + localization sweep across every screen; audit-trail completeness (#46–#50). | ★ privacy (E10) |
| **I — Reliability & Release** | E12 / E13 / E14 | Cold-launch / reconciliation / challenge latency budgets; overnight & travel battery; soak (no memory growth); fault injection; adversarial-review epochs; TestFlight critical matrix; App Store submission. | |

**Cadence note.** CP-B and CP-G are the two moments where the app's core safety promises become
real (it rings; the AI can't harm you). Schedule those as dedicated device sessions the moment
their epochs land — everything else can ride the normal end-of-epoch pass.
