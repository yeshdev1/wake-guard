# Release Checklist

> Run these **incrementally** at epoch boundaries per `docs/UAT_CHECKPOINTS.md`, not all at
> release — most items below belong to a specific checkpoint (CP-A…CP-I).

## Product and safety

- [ ] Core alarm works without HealthKit, location, calendar, or AI.
- [ ] No AI path can call AlarmKit directly.
- [ ] No response to a pre-alarm prompt leaves the original alarm unchanged.
- [ ] A movement-based "likely awake" inference never suppresses or cancels an alarm — at most it surfaces a pre-alarm prompt (#8). Verify a **false** `.likely` (e.g. a car/train commute jostling the phone in a bag) still rings the alarm on time (WG-080 evidence model; wired by WG-082).
- [ ] Bathroom-return-to-bed (**UAT CP-C**, the false-positive trap): a real brief trip to the bathroom during the pre-alarm window at most surfaces a prompt whose default is **keep** and **never cancels/suppresses** the alarm (#8/#7); turning off a **critical** alarm from that prompt still requires explicit confirmation (#6); once back in bed (movement stale) — or when the **pedometer is unavailable/denied** ("couldn't observe", never read as "confirmed still") — **no prompt** appears; and a `.likely` trip in the **final stretch** before the ring (≤120 s critical / ≤60 s standard) does **not** prompt (let it ring) (WG-091).
- [ ] Pre-alarm prompt policy on device (**UAT CP-D**, WG-083 runtime): the evaluator surfaces a prompt **only** inside the lead window when the evidence is `.likely` and **not** in the imminent stretch before ringing (a **critical** alarm uses a more conservative 120 s cutoff); a critical alarm's turn-off from the prompt **requires explicit confirmation** and is submitted as an `AlarmCommand` through `AlarmCommandProcessor` (#6) — never a direct adapter call, and the `requiresConfirmation` flag is honored, not treated as optional; an **unavailable** movement source declines (`.sourceUnavailable`) rather than nudging; and the WG-083 runtime applies a **cooldown / once-per-morning** gate so one finished walk doesn't re-prompt (WG-082 is stateless) (WG-082).
- [ ] Pre-alarm prompt actions on device (**UAT CP-D**): the notification shows **Keep alarm** first (the #7 safe default) plus the configured **Turn off today / Change time / Remind later**, with the **warning** ("original alarm stays scheduled unless you change it") legible; **action titles don't truncate** on the narrowest banner; the destructive turn-off renders distinctly (label, not color alone); **VoiceOver reads the warning before** the destructive actions; every string resolves through `NSLocalizedString` (incl. the notification **body** title/warning, not just action titles) and is ready for E11 localization (WG-083).
- [ ] Keep-alarm action on device (**UAT CP-D**): explicitly tapping **Keep alarm** leaves the alarm ringing exactly on schedule (no schedule change, #7) and adds a **history acknowledgement** entry attributed to the user; a stale keep (the alarm already rang or was deleted) is a safe no-op with no error (WG-084).
- [ ] Turn-off-today action on device (**UAT CP-D**): tapping **Turn off today** stops **today's** ring while the recurring alarm **still rings at the next occurrence** (only the occurrence is affected, not a permanent disable); a **critical** alarm's turn-off **foregrounds and requires explicit confirmation** (#6, via `AlarmCommandProcessor`); a **one-time** alarm's turn-off-today ends it (no remaining occurrence); and — verify the safe direction — if the device time zone changes between turn-off and the occurrence, the alarm **still rings** rather than being silently suppressed (WG-085).
- [ ] Remind-later action on device (**UAT CP-D**, WG-088/089 runtime): tapping **Remind me later** re-shows the pre-alarm prompt after a bounded delay and **stops re-prompting** once the cap is reached (standard 3 / critical 1) or a full deferral no longer fits before the alarm; the **alarm rings exactly on schedule** throughout (its schedule is never touched); and the reminder count **survives app termination / a stale or duplicate notification action** so the cap can't be bypassed at runtime (WG-087).
- [ ] Change-time action on device (**UAT CP-D**, app-shell): tapping **Change time** opens a pre-filled editor (**not** an immediate change); the **original alarm keeps ringing on its schedule until the user saves** and the save succeeds; a **critical** alarm's save requires explicit confirmation (#6) and routes through `AlarmCommandProcessor`; the anchor time zone is preserved (no silent re-anchor, #11/#16); and if the alarm rings while the editor is open, the ring is **not suppressed** (WG-086).
- [ ] Critical alarm cancellation/delay requires explicit confirmation.
- [ ] Critical alarm rings through silent mode, Focus, and Do Not Disturb on a real device (AlarmKit has no app-facing criticality knob — WG-026 assumes the system-alarm baseline; verify — WG-030).
- [ ] AlarmKit + Motion permission prompts show the **purpose strings** (`NSAlarmKitUsageDescription` / `NSMotionUsageDescription`): each names the specific use and the Motion string disclaims location + saved workouts/health records (#41); confirm the app does not crash on first AlarmKit / Core Motion access (the keys are present in the built Info.plist) (runs-on-a-phone step 1).
- [ ] Runs-on-a-phone integration ordering (safety): the app **never claims an alarm rings before authorization is granted** — the "won't ring yet" disclosure stays until the real adapter is composed **and** the permission prompt is wired; flipping `schedulesAlarmsInSystem` true happens only *after* the authorization UI lands, so a first alarm-create is never silently `.notAuthorized` while the UI implies it rings (#7). See DECISIONS "Runs-on-a-phone" plan.
- [ ] Ten-second challenge pass is validated on real devices.
- [ ] Shaking alone does not pass in the accepted test matrix.
- [ ] Accessible non-walking fallback works.
- [ ] Alarm state reconciles on launch/foreground: a **missing** system alarm is re-scheduled, an **extra** one is cancelled, and a **divergent** fire time is corrected, each producing a `systemReconciliation` audit entry (WG-029). Verify the real AlarmKit read-back reports **criticality** — else a critical alarm looks divergent every pass and is redundantly re-scheduled (WG-026/WG-029 seam). Confirm reconciliation never cancels a **currently ringing** alarm (future-only cancel, #24). Requires the launch/foreground trigger + processor composition (follow-on).
- [ ] Every mutation appears in audit history.
- [ ] Error UI states whether the alarm remains scheduled.

## Time

- [ ] DST spring-forward cases pass.
- [ ] DST fall-back cases pass.
- [ ] Half-hour/45-minute zones pass.
- [ ] International Date Line cases pass.
- [ ] Follow-local and fixed-zone semantics are documented and tested.
- [ ] Stale travel prompts are harmless.
- [ ] Manual clock/time-zone changes are tested.

## Lifecycle and reliability

- [ ] App terminated.
- [ ] Device restarted.
- [ ] Low Power Mode.
- [ ] Background App Refresh disabled.
- [ ] Pre-alarm background opportunity on device (**internal**): with Background App Refresh **on**, the `BGAppRefreshTask` runs the pre-alarm evaluation **opportunistically** and **expiration-safely** (yields when the OS reclaims it — no runaway task), **reschedules without a tight loop** (bounded delay, acceptable battery), and a **failed / expired / skipped** run **changes no alarm**; and — the invariant — a **critical alarm rings on schedule even if the BG task never runs** (#9, Background App Refresh off) (WG-088).
- [ ] Pre-alarm prompt de-dup on device (**internal**): after a **background** pre-alarm prompt for an occurrence, **opening the app does not re-show it** for that same occurrence (the persisted idempotency claim survives relaunch); a **new** occurrence prompts once; and a suppressed/de-duplicated prompt **never changes the alarm** — it rings on schedule (WG-089).
- [ ] Notification permission revoked.
- [ ] Motion permission revoked mid-flow.
- [ ] Location/Health/Calendar denied and revoked.
- [ ] Storage/persistence failure.
- [ ] Duplicate/out-of-order callbacks.
- [ ] Async cancellation and uncertain external outcome.
- [ ] 100-cycle soak test.

## Privacy and security

- [ ] Privacy manifest.
- [ ] SDK inventory.
- [ ] Privacy Nutrition Label mapping.
- [ ] In-app privacy policy link.
- [ ] Explicit consent before third-party AI sharing.
- [ ] No raw sensitive logs.
- [ ] Motion trace recorder (WG-074) is **excluded from the release archive** (it is `#if DEBUG`; confirm no symbol in the shipped binary — ties to "Archive contains no debug tools" below); in internal debug builds it records only after the consent warning, exports **anonymized** traces (relative offsets, no wall clock / name / device / location), and the exported traces stay **on-device / internal**, never distributed (a gait/step series is a pseudonymous-behavioral fingerprint).
- [ ] No health/motion/location/calendar advertising use.
- [ ] Pre-alarm feedback is local + coarse (**internal**): "I wasn't awake" / "helpful" is stored **on-device** as a coarse two-counter tally — **no** alarm id, occurrence/fire time, sleep-revealing timestamp, or raw sample (#41); it is **never logged or transmitted**; and it **cannot silently retune critical-alarm behavior** — any advisory use of it to tune the awake model is an explicit, user-initiated step, never automatic (#8/#31) (WG-090).
- [ ] Export works.
- [ ] Deletion works.
- [ ] Secrets audit passes.
- [ ] Prompt injection corpus passes.

## Accessibility and visual quality

- [ ] VoiceOver.
- [ ] Dynamic Type at largest sizes.
- [ ] Reduce Motion.
- [ ] Increased contrast.
- [ ] Dark mode.
- [ ] 12/24-hour formats.
- [ ] RTL.
- [ ] Non-color status indicators.
- [ ] Design-system filled controls (primary / destructive) meet contrast on device against the shipped accent and system red at the smallest Dynamic Type size; the destructive action is distinguishable from the primary **without** color (WG-040).
- [ ] Alarm list on device: the next-ring time stays accurate after an alarm fires (foreground reload) and after a time-zone change; rows and the summary reflow (no truncation) at the largest Dynamic Type; a critical alarm is prominent and VoiceOver announces its criticality first; a failed/unavailable load never reads as "no alarms" (WG-041).
- [ ] Create-alarm on device: each MVP schedule type (weekly, one-time) creates and appears in the list; the next-occurrence preview updates live and honors 12/24-hour; an unsafe date (past one-time / no days / a minute that has lapsed) cannot be saved; a DST-boundary one-time (nonexistent / ambiguous wall-clock time) creates and resolves sensibly; the "won't ring yet" disclosure shows until the real AlarmKit adapter + authorization flow are wired — and once wired, a genuine schedule failure does **not** report "couldn't create" for an alarm that was saved (WG-042).
- [ ] Edit / enable-disable / delete on device: each routes through confirmation where required — a **critical** alarm's delete/disable/edit prompts, and cancelling (or no response) leaves it unchanged (#6); swipe-to-delete needs a deliberate two-step (no one-gesture full-swipe); the enable/disable toggle and the destructive actions are VoiceOver-legible (alarm name + on/off consequence, not color-alone) and reflow at the largest Dynamic Type; a failed action states whether the alarm is still scheduled (#41 coarse); an edit preserves criticality and the alarm remains saved-but-not-ringing until the AlarmKit adapter lands (WG-043).
- [ ] Critical alarm configuration on device: the "Critical alarm" toggle sets/clears criticality and its plain-language explanation is legible and reflows at the largest Dynamic Type; making an alarm critical needs no confirmation but turning it off / weakening it does (#6); no model/AI path can set criticality (#31); the "designed to ring through silent / Focus / Do Not Disturb" behavior is device-verified via SMK-04 once AlarmKit scheduling is wired — the interim adapter doesn't ring yet, so the copy must not present-tense over-promise (WG-044).
- [ ] Wake-challenge configuration on device: the "Wake challenge" section (None/Walk, duration/steps steppers, accessible-alternative picker) is legible and reflows at the largest Dynamic Type; VoiceOver announces each control's label + value; the phone-carry requirement is disclosed and the accessible alternative is clearly always available (#25, SCOPE §2.3); the duration/steps steppers can't be set to a degenerate challenge (the required cadence stays a plausible walk). The actual walk detection / pass-fail is verified separately (WG-072/075) (WG-045).
- [ ] Travel-policy configuration on device: the three options (follow local / keep home-zone / ask) are clear and reflow at the largest Dynamic Type; the anchor IANA zone is shown and VoiceOver reads it naturally (not spelling "New_York" or voicing "/"); the destination preview matches the chosen option; editing an alarm **while in a different time zone does not silently re-anchor** it (#16); no copy implies GPS/location tracking. The runtime travel detection is E06 (WG-046).
- [ ] Pre-alarm configuration on device: the "Smart pre-alarm" section (enable, lead-time window, action toggles) is legible + reflows at the largest Dynamic Type; VoiceOver reads the toggle/stepper (label + value) and each action toggle (+ hint); the disclosure clearly states that **no response leaves the alarm unchanged** (#7), notes an enabled-with-no-actions prompt is informational-only, and — for a critical alarm — shows that turning it off from the prompt needs confirmation (#6). The pre-alarm prompt runtime is E05 (WG-047).
- [ ] Alarm history on device: opening "History" from an alarm lists who/what/when for each change in plain language; a system/recovery/reconciliation entry is visibly distinct (icon + "System" tag, not color-alone) and reads "System action…" to VoiceOver (#50); the detail shows no raw hashes / ids / internal state (#41); a failed load reads distinctly from "no history yet"; rows + tags reflow at the largest Dynamic Type without truncating the outcome (WG-048).
- [ ] Deep links on device (**requires the `wakeguard://` URL scheme registered first** — WG-049 deferred that Info.plist step to the notification/AlarmKit work): opening `wakeguard://alarm/<id>` opens that alarm (no auto-change — #7); a deleted/unknown id and a `wakeguard://proposal/<id>` show a safe message, never a wrong or blank screen; a malformed link is a safe no-op; a link arriving while a create/edit sheet is open still lands the user on the target (the single-presenter consolidation) (WG-049).
- [ ] UI-test suite + screenshot baseline: `make test-ui` passes the six core flows (create / edit / delete / critical-delete-confirm / travel) on the release build's simulator; the attached key-state screenshots are reviewed and approved as the visual baseline; and the UI suite is wired into the fuller (non-fast) CI matrix (WG-050).
- [ ] Motion & Fitness permission on device (**UAT CP-C**): the request appears **in context** (setting up a walk challenge) *after* the specific purpose explanation, never at launch; declining — or a restricted/interrupted state — still lets the user turn off the alarm via the accessible tap / press-and-hold challenge (#21); the purpose copy names the specific use and disclaims location + saved workouts/health records (#41). Authorized-but-no-pedometer-hardware falls back to the alternative (WG-061).
- [ ] Historical pedometer on device (**UAT CP-C**): a bounded-window `CMPedometer` history query returns a validated step sample; a query whose data is missing/denied/no-hardware **throws** (never a silent empty that would read as "user was still") and the walk challenge falls back to the accessible alternative; the window can't read the future or an over-long range; and **no raw sample values or CoreMotion error text appear in any log** (#41) — a query failure surfaces only as the coarse "temporarily unavailable" state (WG-062).
- [ ] Recent movement query on device (**UAT CP-D**, WG-082 wiring): the pre-alarm feeder pulls recent steps from a **bounded, on-demand** `CMPedometer` history query (a handful of one-shot reads) with **no continuous overnight sensing** — confirm no background/live sensing runs across the night and overnight idle battery is unaffected; an unavailable/denied pedometer surfaces as **`sourceAvailable == false`** (couldn't observe), never a false "still"; and the recency read is a coarse **upper bound** quantized to the query rungs, not a precise last-step time (WG-081).
- [ ] Live pedometer on device (**UAT CP-C**): a real walk produces a live step stream that reaches the walk challenge; **cancelling the challenge (or leaving the screen) stops `CMPedometer` updates** — confirm no pedometer updates keep running in the background (battery + privacy); duplicate/out-of-order/glitched deliveries don't corrupt progress and a mid-walk counter reset doesn't produce negative progress; a denied/no-hardware source **throws** (never a silent empty that reads as "didn't walk") → accessible alternative; and **no raw sample values or CoreMotion error text appear in any log** (#41) (WG-063).
- [ ] Motion activity on device (**UAT CP-C**): a real walk classifies as `walking` (single-flag) and reaches the challenge; a transition (e.g. walking+automotive) resolves to `unknown` rather than a false confident class; cancelling the challenge **stops `CMMotionActivityManager` updates** (no background leak); an **unsupported device** (no activity classifier) or a denied grant **throws** → accessible alternative (never an empty "no activity = stationary/asleep" stream); confidence is preserved and no raw activity state appears in logs (#41) (WG-064).
- [ ] Device-motion evidence on device (**UAT CP-C**): on real motion the evidence classifies a **still** phone as stationary, a genuine **pickup/carry** as pickup, and a **shake-on-nightstand** as irregular-shaking (never as pickup); a **slow deliberate tilt** may read as pickup (a known limitation — the walk challenge, not this evidence, is the wake gate); **calibrate the `DeviceMotionEvidenceAnalyzer` thresholds** on real still/pickup/shake motion (the CI defaults are cautious placeholders); confirm the evidence never claims a distance/displacement (WG-065).
- [ ] Altimeter evidence on device (**UAT CP-C**): a real stand-up / stairs corroborates movement (`significantChange`) while sitting still or normal weather/HVAC pressure drift does **not** (stays flat); a phone with **no barometer** has zero negative impact on any challenge (never a penalty); confirm a lone altitude `significantChange` alone does **not** pass a challenge (it only corroborates pedometer/accel movement — a fast door/HVAC/elevator transient looks the same to barometry); **calibrate the `AltitudeEvidenceAnalyzer` thresholds** on device (WG-066).
- [ ] Movement episodes on device (**UAT CP-C/CP-D**, via the challenge): a real continuous walk forms one sustained episode while lying-in-bed tossing does not; a genuine pause splits episodes; a stale or replayed observation stream cannot form a *fresh* episode (the freshness gate); calibrate `MovementEpisodeBuilder` `pauseGap` / `staleHorizon` on device (WG-067).
- [ ] Wake challenge outcomes on device (**UAT CP-C/CP-D**): a genuinely-walked challenge reaches **passed** and only then lets the user dismiss; a **timed-out**, **interrupted/failed**, or **sensor-unavailable** challenge keeps the alarm ringing and offers the accessible alternative (never dismisses); replayed/duplicate step data cannot inflate progress to a false pass; the ring-stop path consults the challenge's `permitsAlarmDismissal` (a valid terminal pass), never a raw notification action (WG-068; ring-stop gating verified in WG-073).
- [ ] Challenge pass → authorized stop on device (**UAT CP-B**, once the real AlarmKit adapter is composed — WG-026): a genuinely-passed challenge (walk **or** the accessible alternative) actually **stops the ringing alarm**; a **timed-out / failed / unavailable** challenge never stops it; a **duplicate or racing** pass (UI event + notification action) stops the ring exactly once and doesn't error; an **uncertain** stop is not recorded as "stopped" (the ring is re-completable — a ring never silently looks handled); the **audit history** shows the stop with the correct actor/source; and the **next occurrence still fires** (a stop ends the ring, not the schedule) (WG-073).
- [ ] Ten-second walking verification on device (**UAT CP-C/CP-D**): a genuine ~10 s walk verifies (`passed`); standing still, a quick pickup, or a brief sub-10 s movement does **not**; the configured duration/steps/density thresholds can be made stricter but never below the safe floor (the ten-second minimum always holds). **Shaking caveat — the walk verification alone does NOT reject a rhythmic shake that produces pedometer steps; that must be confirmed rejected once WG-070 (anti-shake/replay) lands** and belongs on the "shaking alone does not pass" matrix line above (WG-069).
- [ ] Cadence anti-shake on device (**UAT CP-C/CP-D + WG-075 calibration**): once the challenge wires in the cadence verdict, confirm the "**shaking alone does not pass**" matrix line — noting the CV-model residual that a *regular ~2/s* shake corroborates cadence, so passing must still require multiple independent signals (#19/#20), never cadence alone; **calibrate the `CadenceThresholds` bands** and verify the documented false-positives are acceptable (a **treadmill** walker → `.tooRegular`, a **slow/elderly** gait > 1.2 s/step → `.implausibleTiming` are wrongly rejected but always have the accessible alternative); confirm `minimumIntervals` fits the device's real pedometer delivery rate (WG-070/075).
- [ ] Calibration study run (**WG-075**, `docs/CALIBRATION.md`): execute the full test matrix (hand / pocket / bag × slow / brisk gait, plus still / pickup / stairs / shake attempts) on real devices with ≥ 3 testers, recording **anonymized** WG-074 traces (no participant identifiers); choose thresholds that reject every cheat with margin (favor the safe/stricter direction — a false fail has the accessible alternative, a false pass does not); **record the chosen `CalibrationProfile` values + residuals in the WG-075 ADR**; re-run the matrix against the tuned profile to confirm no regression before it replaces the baseline; confirm the paced-shake residual is closed by a second signal, not a loosened threshold.
- [ ] Challenge screen on device (**UAT CP-C/CP-D**): while the challenge runs the alarm reads **clearly active until pass** (status badge + headline, icon+label not color-alone) and only a genuine pass shows "Alarm off"; the big progress ("X of Y steps" + bar) is legible during sleep inertia; **VoiceOver speaks progress on step milestones and the outcome on pass / not-pass** (announce-on-change, not just on re-focus), and the "Can't walk?" fallback is separately focusable and always reachable; **haptics fire** (a light tick on progress milestones — no fatigue — and a distinct success / warning on pass / not-pass); at the largest Dynamic Type nothing truncates and the fallback stays pinned; Reduce Motion stops the bar animation; dark mode / Increase Contrast hold (WG-071).
- [ ] Accessible alternative on device (**UAT CP-C/CP-D**, WG-075): from the challenge's "Can't walk? Use another way", the preselected alternative (tap sequence / press-and-hold) turns the alarm off; a **VoiceOver / Switch Control user can complete both kinds** — the hold via an activation, **not** a sustained press (no dead-end); the live count + per-tap speech make progress clear for low-vision / blind users; a single accidental or stuck touch does **not** pass; the framing is non-stigmatizing; **motor-impaired users should be steered to the tap sequence** (the picker recommends it). Confirm the completion routes to the authorized stop only (WG-073) (WG-072).
- [ ] Touch targets.
- [ ] Sleep-inertia usability.
- [ ] Approved screenshot baseline.
- [ ] All key empty/loading/error/success states.

## Performance and battery

- [ ] Cold-launch budget.
- [ ] Reconciliation budget.
- [ ] Challenge start/pass latency.
- [ ] Overnight idle battery.
- [ ] Location/travel battery.
- [ ] Device-motion (CMDeviceMotion) battery cost measured at the challenge's sampling rate/window — the device-carried/pickup evidence runs on a bounded window, so continuous high-rate sampling must not be required (WG-065).
- [ ] No memory growth in soak test.
- [ ] AI latency has deterministic fallback.

## Store submission

- [ ] Latest stable toolchain accepted by App Store.
- [ ] Archive contains no debug tools.
- [ ] App Review notes explain AlarmKit, challenge, optional permissions, and AI safety.
- [ ] Metadata contains no diagnostic claims.
- [ ] Screenshots match shipping build.
- [ ] Support URL and privacy URL work.
- [ ] Demo steps work for reviewer.
- [ ] TestFlight critical matrix passed on exact build.
- [ ] Rollback and smart-feature kill-switch plan exists.
