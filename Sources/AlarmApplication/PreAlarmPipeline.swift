import Foundation

/// The pre-alarm evaluation pipeline (WG-08x composition) — the advisory `work` a background
/// opportunity (WG-088) or a foreground app launch (WG-089) runs. It ties the E05 primitives together:
/// recent-movement query (WG-081) → awake evidence + prompt policy (WG-080/082) → prompt de-dup
/// (WG-089) → prompt content (WG-083). It holds **no alarm authority** — it decides only whether to
/// surface a prompt and what it says, never touching the alarm (advisory throughout, #7/#8).
struct PreAlarmPipeline: Sendable {
    let movementQuery: RecentMovementQuery
    let coordinator: PreAlarmPromptCoordinator
    var evaluatorConfig: PreAlarmEvaluator.Config = .default

    /// Evaluate an alarm's upcoming occurrence and return the prompt to present, or `nil` to surface
    /// nothing (declined, or already surfaced for this occurrence). `now`/`timeRemaining` are injected;
    /// `deviceInteracted` is the optional device-interaction signal. Never mutates the alarm.
    func evaluate(
        alarm: Alarm, occurrence: Date, timeRemaining: TimeInterval, deviceInteracted: Bool,
        now: Date
    ) async -> PreAlarmPromptContent? {
        let snapshot = await movementQuery.snapshot(now: now)
        let recommendation = PreAlarmEvaluator.evaluate(
            policy: alarm.preAlarmPolicy, criticality: alarm.criticality,
            timeRemaining: timeRemaining, movement: snapshot, deviceInteracted: deviceInteracted,
            config: evaluatorConfig)
        let key = PreAlarmPromptKey(alarmID: alarm.id, occurrence: occurrence)
        guard await coordinator.surface(recommendation, for: key, at: now) else { return nil }
        return PreAlarmPromptContent.from(recommendation)
    }
}
