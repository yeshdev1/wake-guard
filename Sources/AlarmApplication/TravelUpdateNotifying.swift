import Foundation

/// Posts the informational "your alarms were updated for the new time zone" notification (WG-304).
/// Advisory only — best-effort and permission-gated: if notifications are denied it is a no-op and the
/// change is still visible in the History/audit trail. It never touches an alarm; a missed notification
/// never affects whether an alarm rings (#9).
protocol TravelUpdateNotifying: Sendable {
    func notifyAlarmsUpdated(forNewZone zone: IANATimeZone) async
}

/// The pure decision for whether a time-zone reconcile warrants a travel notification (WG-304): notify
/// **only** when the reconcile actually moved an enabled alarm (scheduled or cancelled a system alarm).
/// No change (e.g. every alarm is "stay fixed", or there are no alarms) ⇒ no notification. A skipped
/// reconcile (the system authority was unreadable) ⇒ no notification.
enum TravelNotificationPolicy {
    static func shouldNotify(summary: ReconciliationSummary) -> Bool {
        guard !summary.skipped else { return false }
        return summary.scheduled > 0 || summary.cancelled > 0
    }
}

/// Glues a detected device time-zone change to the reconcile + the FYI notification (WG-304). Extracted
/// from the monitor's `onChange` so the "reconcile → notify only when something changed" logic is unit
/// testable. Holds no alarm authority beyond the processor's own boundary (#2).
struct TravelUpdateCoordinator: Sendable {
    private let processor: any AlarmCommandProcessing
    private let notifier: any TravelUpdateNotifying

    init(processor: any AlarmCommandProcessing, notifier: any TravelUpdateNotifying) {
        self.processor = processor
        self.notifier = notifier
    }

    /// Reconcile alarms into the new zone, then notify **only** if that actually shifted an alarm.
    func handleZoneChange(_ change: TimeZoneChange) async {
        let summary = await processor.reconcile()
        guard TravelNotificationPolicy.shouldNotify(summary: summary) else { return }
        await notifier.notifyAlarmsUpdated(forNewZone: change.current)
    }
}
