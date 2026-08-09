import Foundation

/// Why the pre-alarm evaluator reached its decision (WG-082) — inspectable + honest about which gate
/// fired. String-raw so an unknown persisted value fails to decode (#27).
enum PreAlarmReason: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Pre-alarm checking is not enabled for this alarm.
    case disabledByPolicy
    /// The alarm is too far off, or too imminent, for a useful prompt (the time-remaining gate).
    case outsideLeadWindow
    /// The awake evidence did not clear the bar — a single weak signal is never enough (WG-080).
    case insufficientEvidence
    /// The movement source couldn't be observed (WG-081 `sourceAvailable == false`) — distinct from
    /// "confirmed still": we didn't get to look, so we don't nudge (fail-closed).
    case sourceUnavailable
    /// Prompt: enabled, within the lead window, and the evidence corroborates the sleeper is awake.
    case awakeWithinWindow
}

/// The pre-alarm evaluator's recommendation (WG-082). It **only recommends whether to surface a
/// pre-alarm prompt** — it carries no cancel, command, or mutation, so a movement inference can never
/// directly cancel an alarm (#8). Any destructive action a critical alarm's prompt offers requires
/// explicit confirmation (`requiresConfirmation`, #6 — enforced by the prompt runtime + policy
/// engine, not here). If the user doesn't respond, nothing changes (#7). The `evidence` and `reason`
/// make the recommendation fully inspectable.
struct PreAlarmRecommendation: Sendable, Equatable {
    let reason: PreAlarmReason
    /// The actions the prompt should offer — a subset of the user's policy; empty when not prompting
    /// or for a purely informational prompt (the user still keeps the alarm by default, #7).
    let offeredActions: Set<PreAlarmAction>
    /// Whether a destructive offered action needs explicit confirmation before it can proceed (#6).
    let requiresConfirmation: Bool
    /// The awake evidence considered (advisory; WG-080).
    let evidence: AwakeEvidence

    /// The recommendation is purely to prompt — never to change the alarm.
    var shouldPrompt: Bool { reason == .awakeWithinWindow }
}

extension PreAlarmAction {
    /// Whether choosing this action would change or stop the alarm — such actions on a critical alarm
    /// need explicit confirmation (#6). `remindLater` is non-destructive.
    var isDestructive: Bool { self == .turnOffToday || self == .changeTime }
}

/// Decides whether to surface a pre-alarm prompt (WG-082) — the "then apply prompt policy" half of
/// E05, after WG-081 + WG-080 have produced the awake evidence. Pure and deterministic; `now` /
/// `timeRemaining` are injected. It **only recommends whether to prompt** and holds no alarm
/// authority, so movement never directly cancels (#8); a no-response leaves the alarm unchanged (#7);
/// a critical alarm's destructive actions are flagged for confirmation (#6). Both **criticality and
/// time remaining influence the policy**: time remaining gates the lead window, and criticality both
/// requires confirmation for destructive actions and applies a more conservative "too imminent"
/// cutoff so a critical alarm is not nudged in the final stretch before it rings.
enum PreAlarmEvaluator {

    struct Config: Sendable, Equatable {
        /// Below this time-to-alarm a standard alarm's prompt is suppressed — the alarm is imminent,
        /// let it ring.
        var minimumTimeRemaining: TimeInterval
        /// The more conservative cutoff for a **critical** alarm — it is not prompted this close to
        /// ringing (criticality × time-remaining influence).
        var criticalMinimumTimeRemaining: TimeInterval

        static let `default` = Config(minimumTimeRemaining: 60, criticalMinimumTimeRemaining: 120)

        func minimumTimeRemaining(for criticality: Criticality) -> TimeInterval {
            criticality == .critical ? criticalMinimumTimeRemaining : minimumTimeRemaining
        }
    }

    /// Evaluate against pre-computed awake evidence (WG-080).
    static func evaluate(
        policy: PreAlarmPolicy, criticality: Criticality, timeRemaining: TimeInterval,
        evidence: AwakeEvidence, config: Config = .default
    ) -> PreAlarmRecommendation {
        func decline(_ reason: PreAlarmReason) -> PreAlarmRecommendation {
            PreAlarmRecommendation(
                reason: reason, offeredActions: [], requiresConfirmation: false, evidence: evidence)
        }
        guard policy.isEnabled else { return decline(.disabledByPolicy) }
        // Time-remaining gate: within the lead window, and not so imminent the prompt is pointless.
        // A non-finite / negative `timeRemaining` fails the lower bound → declines (fail-closed); a
        // non-finite `leadTime` (defense-in-depth — the factory already rejects it) would otherwise
        // collapse the upper bound, so it is guarded here too.
        guard timeRemaining.isFinite, policy.leadTime.isFinite,
            timeRemaining > config.minimumTimeRemaining(for: criticality),
            timeRemaining <= policy.leadTime
        else { return decline(.outsideLeadWindow) }
        // Evidence gate: only a corroborated "likely awake" prompts — WG-080 guarantees `.likely`
        // cannot come from a single weak signal. A movement inference short of this never prompts,
        // and even when it does, it only *prompts* — it never cancels (#8).
        guard evidence.likelihood == .likely else { return decline(.insufficientEvidence) }
        let requiresConfirmation =
            criticality == .critical && policy.allowedActions.contains { $0.isDestructive }
        return PreAlarmRecommendation(
            reason: .awakeWithinWindow, offeredActions: policy.allowedActions,
            requiresConfirmation: requiresConfirmation, evidence: evidence)
    }

    /// Evaluate from a recent-movement snapshot (WG-081): build the awake evidence via the WG-080
    /// model, then apply the prompt policy. The aggregate history carries no episode timeline, so the
    /// sustained-episode factor is absent here (`longestEpisodeDuration = 0`) — recent steps + recency
    /// (+ an optional device interaction) drive the evidence. That is the exact pair passive transport
    /// corroborates, so a commute's false `.likely` (WG-080's pinned residual) surfaces a prompt here;
    /// tolerable only because it is advisory — no response keeps the alarm (#7) and it never cancels
    /// (#8). An unavailable source declines with `.sourceUnavailable` (not `.insufficientEvidence`) so
    /// "couldn't observe" is never conflated with "confirmed still". WG-082 is intentionally
    /// **stateless**: prompt de-duplication / cooldown / once-per-morning gating is the WG-083
    /// runtime's job — a finished walk keeps reading `.likely` until it ages out of the widest recency
    /// rung, so a cooldown there is required, not optional.
    static func evaluate(
        policy: PreAlarmPolicy, criticality: Criticality, timeRemaining: TimeInterval,
        movement: RecentMovementSnapshot, deviceInteracted: Bool = false, config: Config = .default,
        evidenceConfig: AwakeEvidenceModel.Config = .default
    ) -> PreAlarmRecommendation {
        let input = AwakeEvidenceInput(
            recentStepCount: movement.stepCount, longestEpisodeDuration: 0,
            secondsSinceLastMovement: movement.secondsSinceLastMovement,
            deviceInteracted: deviceInteracted)
        let evidence = AwakeEvidenceModel.evaluate(input, config: evidenceConfig)
        // Honor WG-081's `sourceAvailable` explicitly — not via the coincidence that an unavailable
        // source reports 0 steps — so a future degraded source that reports steps while unavailable
        // still can't nudge, and the *reason* stays honest for a later explanation UI (#32).
        guard movement.sourceAvailable else {
            return PreAlarmRecommendation(
                reason: .sourceUnavailable, offeredActions: [], requiresConfirmation: false,
                evidence: evidence)
        }
        return evaluate(
            policy: policy, criticality: criticality, timeRemaining: timeRemaining,
            evidence: evidence, config: config)
    }
}
