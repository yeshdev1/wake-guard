import Foundation

/// One option a time-zone-change prompt offers (WG-105): a `ScheduleZoneResolution` plus a concrete
/// preview of when the alarm would next ring under it, so the user compares old vs new **ring times**
/// with full information. `nextRing` is `nil` when the alarm wouldn't ring (e.g. a one-time alarm whose
/// only occurrence is already past) — the UI shows "won't ring", never a wrong time.
struct TimeZoneChangePromptOption: Sendable, Equatable, Hashable {
    let resolution: ScheduleZoneResolution
    /// The absolute instant the alarm would next ring under this resolution, or `nil` if it wouldn't.
    let nextRing: Date?
    /// The IANA zone this option interprets the schedule in — the anchor for keep, the device's new zone
    /// for follow-local. Lets the UI render the ring time in the relevant wall clock (#11).
    let zone: IANATimeZone
    /// How the previewed ring resolved against a DST transition **in `zone`** (WG-106) — `nil` when it
    /// won't ring. Travel and DST compose here: a follow-local preview at the destination surfaces a
    /// skipped (spring-gap → gap-end) / duplicated (fall-back → earlier) / date-line-shifted local time,
    /// so the prompt can explain it (e.g. "2:30 is skipped at your destination; it rings at 3:00").
    let dstResolution: DSTResolution?
}

/// What the user chose (or didn't) at a time-zone-change prompt (WG-105).
enum TimeZoneChangePromptResponse: Sendable, Equatable, Hashable {
    /// The prompt was dismissed / timed out with no choice — the documented default must stand (#7).
    case noResponse
    /// Keep the alarm anchored to its original zone (no shift).
    case keepAnchor
    /// Follow local time. `confirmed` records whether the user cleared the confirmation step a critical
    /// change requires (#6).
    case followLocal(confirmed: Bool)
}

/// The outcome of a prompt response (WG-105) — advisory only; the actual reschedule is the policy
/// engine's job. Distinguishes the safe "nothing changes" paths from an explicit apply and from a
/// critical change still awaiting confirmation.
enum TimeZoneChangePromptEffect: Sendable, Equatable, Hashable {
    /// No response: the documented default stands and the alarm is unchanged (#7).
    case keepAsDocumented(ScheduleZoneResolution)
    /// Apply the chosen resolution — safe now (non-critical, or a critical change the user confirmed).
    case apply(ScheduleZoneResolution)
    /// A critical follow-local change awaits explicit confirmation (#6); nothing is applied yet.
    case needsConfirmation
}

/// The prompt shown when the device time zone changes and an alarm's policy is `askOnChange` (WG-105).
/// Previews the old (keep-anchor) and new (follow-local) ring times so the user chooses with full
/// information. Advisory and safe by construction: **no response preserves the documented default** —
/// keep the anchor (#7/#16) — and a change to a **critical** alarm requires explicit confirmation (#6).
/// It holds no alarm authority: `resolve` only classifies the response; the reschedule is the policy
/// engine's, gated by that confirmation.
struct TimeZoneChangePrompt: Sendable, Equatable, Hashable {
    let zoneChange: TimeZoneChange
    /// The option that applies if the user does nothing — always the safe anchor (#7/#16).
    let standingOption: TimeZoneChangePromptOption
    /// The alternative (follow-local) the prompt offers.
    let alternativeOption: TimeZoneChangePromptOption
    /// Whether *applying the alternative* requires explicit confirmation — `true` iff the alarm is
    /// critical (a critical change confirms, #6). Keeping the anchor is never a change, so never needs it.
    let alternativeRequiresConfirmation: Bool
    /// The recorded-factor explanation carried from the WG-104 decision (#32).
    let explanation: String

    /// The resolution that stands if the user does not respond — the documented default (#7).
    var noResponseResolution: ScheduleZoneResolution { standingOption.resolution }

    /// Classifies a response into its safe effect. No response keeps the documented default (#7); an
    /// explicit follow-local on a critical alarm needs confirmation first (#6).
    func resolve(_ response: TimeZoneChangePromptResponse) -> TimeZoneChangePromptEffect {
        switch response {
        case .noResponse:
            .keepAsDocumented(noResponseResolution)
        case .keepAnchor:
            .apply(.keepAnchorZone)
        case .followLocal(let confirmed):
            alternativeRequiresConfirmation && !confirmed
                ? .needsConfirmation
                : .apply(.followDeviceZone)
        }
    }
}

/// Builds a `TimeZoneChangePrompt` from a WG-104 `TravelPolicyDecision`, previewing the next ring under
/// each option (WG-105). Pure — the ring previews come from the deterministic `AlarmSchedulingEngine`
/// given an injected `now`; no clock or ambient state is read.
struct TimeZoneChangePromptBuilder: Sendable {
    let engine: AlarmSchedulingEngine

    init(engine: AlarmSchedulingEngine = AlarmSchedulingEngine()) {
        self.engine = engine
    }

    /// A prompt for `alarm` given the decision and the detected `zoneChange`, or `nil` when the decision
    /// is deterministic (`.resolved`) — only `askOnChange` (`.prompt`) surfaces a prompt. Ring previews
    /// are the next occurrence strictly after `now` in each option's zone.
    func makePrompt(
        for alarm: Alarm, decision: TravelPolicyDecision, zoneChange: TimeZoneChange, now: Date
    ) -> TimeZoneChangePrompt? {
        // Only `askOnChange` (a `.prompt` decision, WG-104) surfaces a prompt; deterministic behaviors
        // need none. WG-105 pins the prompt's structure **itself** — standing = keep the anchor,
        // alternative = follow-local — rather than trusting the decision's `standing`/`alternative`
        // payload, so the #7/#16 no-response default is the safe anchor *by construction at this
        // boundary*, independent of how (or whether) WG-104 later labels the options.
        guard case .prompt = decision.outcome else { return nil }
        return TimeZoneChangePrompt(
            zoneChange: zoneChange,
            standingOption: option(.keepAnchorZone, alarm: alarm, zoneChange: zoneChange, now: now),
            alternativeOption: option(
                .followDeviceZone, alarm: alarm, zoneChange: zoneChange, now: now),
            alternativeRequiresConfirmation: alarm.criticality == .critical,
            explanation: decision.explanation)
    }

    private func option(
        _ resolution: ScheduleZoneResolution, alarm: Alarm, zoneChange: TimeZoneChange, now: Date
    ) -> TimeZoneChangePromptOption {
        let zone =
            resolution == .followDeviceZone ? zoneChange.current : alarm.schedule.anchorTimeZone
        // Compose travel-zone selection with the WG-022/023 DST/IDL policy (WG-106): resolve the ring in
        // `zone` and carry how it landed, so a destination-zone gap/duplicate/date-line shift is surfaced.
        let resolved = engine.resolvedNextOccurrence(
            of: alarm.schedule, after: now, in: zone.timeZone)
        return TimeZoneChangePromptOption(
            resolution: resolution, nextRing: resolved?.date, zone: zone,
            dstResolution: resolved?.resolution)
    }
}
