import Foundation

/// The pre-alarm evaluation `work` (runs-on-a-phone step 6): the advisory pass a foreground app launch
/// (WG-089) or a background opportunity (WG-088, via `PreAlarmBackgroundRunner`) runs. For each enabled
/// alarm whose next occurrence is inside its pre-alarm lead window, it runs the `PreAlarmPipeline`
/// (movement → awake evidence → prompt policy → de-dup) and, when a prompt is recommended, **posts** the
/// advisory notification.
///
/// Holds **no alarm authority** (#7/#8): it only reads alarms + posts a notification — it never
/// schedules, cancels, or mutates an alarm, so a failed/skipped pass changes nothing and a critical
/// alarm rings regardless (#9). Fail-safe: an unreadable repository posts nothing. Cooperatively
/// cancellable (a background expiry cancels the task) — it checks `Task.isCancelled` between alarms.
struct PreAlarmBackgroundWork: Sendable {
    let alarms: any AlarmRepository
    let pipeline: PreAlarmPipeline
    let notifications: any PreAlarmNotificationScheduling
    var engine = AlarmSchedulingEngine()
    let deviceTimeZone: @Sendable () -> TimeZone

    func run(now: Date) async {
        guard let all = try? await alarms.allAlarms() else { return }
        let zone = deviceTimeZone()
        for alarm in all where alarm.isEnabled && alarm.preAlarmPolicy.isEnabled {
            if Task.isCancelled { return }
            guard
                let occurrence = engine.nextOccurrence(for: alarm, after: now, deviceTimeZone: zone)
            else { continue }
            let timeRemaining = occurrence.timeIntervalSince(now)
            // Only inside the lead window; the pipeline applies the tighter "not too imminent" +
            // evidence + de-dup gates and returns nil to post nothing.
            guard timeRemaining > 0, timeRemaining <= alarm.preAlarmPolicy.leadTime else {
                continue
            }
            let content = await pipeline.evaluate(
                alarm: alarm, occurrence: occurrence, timeRemaining: timeRemaining,
                deviceInteracted: false, now: now)
            guard content != nil else { continue }
            await notifications.postPrompt(
                PreAlarmResponseContext(
                    alarmID: alarm.id, occurrence: occurrence, criticality: alarm.criticality,
                    remindersUsed: 0), at: now)
        }
    }
}
