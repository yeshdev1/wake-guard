import Foundation

/// Which zone an alarm's wall-clock schedule is interpreted in after a detected travel event (WG-104).
/// Mirrors the two intents of `TravelBehavior` (#12): follow the device's new local zone, or keep the
/// alarm's original anchor. Derived **only** from the user's behavior + the confirmed system zone change
/// — never from location, which can neither force nor block it (see `TravelPolicyEvaluator`).
enum ScheduleZoneResolution: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// Follow-local: interpret the wall-clock in the device's new zone, so the alarm keeps ringing at the
    /// same clock time locally.
    case followDeviceZone
    /// Stay-fixed: keep the alarm's original anchor zone, so it rings at the same absolute instant
    /// regardless of travel.
    case keepAnchorZone
}

/// The deterministic, advisory outcome of evaluating a detected travel event against one alarm's
/// `TravelBehavior` (WG-104). Explainable (#32) and holding **no alarm authority** — it mutates nothing
/// and re-anchors nothing (that is the policy engine's job, gated by confirmation). A `prompt` always
/// carries a **safe standing default** that stands until the user explicitly chooses (#7/#16).
struct TravelPolicyDecision: Sendable, Equatable, Hashable {
    /// Apply a resolution silently (the user's pre-chosen deterministic behavior), or surface an advisory
    /// prompt (`askOnChange`) whose standing default preserves the anchor.
    enum Outcome: Sendable, Equatable, Hashable {
        /// Deterministic: apply this resolution, no prompt — the user pre-chose this behavior.
        case resolved(ScheduleZoneResolution)
        /// Surface an advisory prompt. `standing` applies until the user chooses (no response → the
        /// anchor, #7/#16); `alternative` is the other option the prompt offers.
        case prompt(standing: ScheduleZoneResolution, alternative: ScheduleZoneResolution)
    }

    let outcome: Outcome
    /// A human-readable rationale derived from recorded factors (#32): the zone change and the user's
    /// behavior preference, plus a coarse note on whether location corroborated (never a coordinate).
    let explanation: String
    /// The recorded factors behind the decision (#32): the time-zone change and the user preference.
    let evidence: [EvidenceReference]
}

/// Turns a detected travel event (`TravelContext`, WG-101) into a deterministic, explainable policy
/// decision for one alarm (WG-104), per its `TravelBehavior`. Pure — no clock, no I/O, no mutation.
///
/// **Location can never silently override the system zone.** The decision's `outcome` is a function of
/// the user's `TravelBehavior` and the **confirmed system zone change** (WG-100) *only* — the
/// `TravelContext` location corroboration is used solely to word the explanation, never to change which
/// zone is chosen. So location can neither *force* a re-anchor (a VPN-suspected `zoneChangeOnly` still
/// applies the user's behavior) nor *block* one (denied location doesn't stop follow-local on a real
/// trip). For `askOnChange` the standing default is always the safe anchor — a change is never applied
/// without an explicit choice (#16), and no response leaves the alarm on its documented default (#7).
struct TravelPolicyEvaluator: Sendable {

    func evaluate(
        travel: TravelContext, behavior: TravelBehavior, anchorZone: IANATimeZone
    ) -> TravelPolicyDecision {
        let evidence = evidenceReferences(travel, behavior: behavior)
        switch behavior {
        case .followLocal:
            return decision(.resolved(.followDeviceZone), travel, anchorZone, evidence)
        case .stayFixed:
            return decision(.resolved(.keepAnchorZone), travel, anchorZone, evidence)
        case .askOnChange:
            return decision(
                .prompt(standing: .keepAnchorZone, alternative: .followDeviceZone),
                travel, anchorZone, evidence)
        case .regionRule(let rule):
            let resolution: ScheduleZoneResolution =
                rule.safeFallback == .followLocal ? .followDeviceZone : .keepAnchorZone
            return decision(.resolved(resolution), travel, anchorZone, evidence)
        }
    }

    private func decision(
        _ outcome: TravelPolicyDecision.Outcome, _ travel: TravelContext,
        _ anchorZone: IANATimeZone, _ evidence: [EvidenceReference]
    ) -> TravelPolicyDecision {
        TravelPolicyDecision(
            outcome: outcome,
            explanation: explanation(outcome, travel, anchorZone: anchorZone),
            evidence: evidence)
    }

    // MARK: - Explanation (from recorded factors only, #32)

    private func explanation(
        _ outcome: TravelPolicyDecision.Outcome, _ travel: TravelContext, anchorZone: IANATimeZone
    ) -> String {
        let change = travel.zoneChange
        let corroboration =
            travel.certainty == .corroboratedByLocation
            ? "A significant location change corroborates this trip."
            : "There is no location corroboration — this could be a VPN or a manual clock change."
        return
            "Time zone changed from \(change.previous.identifier) to \(change.current.identifier). "
            + actionClause(outcome, current: change.current, anchorZone: anchorZone) + " "
            + corroboration
    }

    private func actionClause(
        _ outcome: TravelPolicyDecision.Outcome, current: IANATimeZone, anchorZone: IANATimeZone
    ) -> String {
        switch outcome {
        case .resolved(.followDeviceZone):
            "This alarm follows local time, so it will keep ringing at its usual clock time in "
                + "\(current.identifier)."
        case .resolved(.keepAnchorZone):
            "This alarm stays fixed to \(anchorZone.identifier), so it rings at the same absolute time "
                + "regardless of travel."
        case .prompt:
            "You chose to be asked on a time-zone change; until you choose, it stays fixed to "
                + "\(anchorZone.identifier)."
        }
    }

    // MARK: - Evidence (recorded factors, no coordinates)

    private func evidenceReferences(
        _ travel: TravelContext, behavior: TravelBehavior
    ) -> [EvidenceReference] {
        [
            EvidenceReference(
                kind: .timeZoneChange,
                reference:
                    "\(travel.zoneChange.previous.identifier)->\(travel.zoneChange.current.identifier)"
            ),
            EvidenceReference(
                kind: .userPreference, reference: "travelBehavior:\(behaviorToken(behavior))"),
        ]
    }

    private func behaviorToken(_ behavior: TravelBehavior) -> String {
        switch behavior {
        case .followLocal: "followLocal"
        case .stayFixed: "stayFixed"
        case .askOnChange: "askOnChange"
        case .regionRule(let rule): "regionRule:\(rule.safeFallback.rawValue)"
        }
    }
}
