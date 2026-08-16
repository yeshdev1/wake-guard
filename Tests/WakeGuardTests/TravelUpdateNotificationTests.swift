import Foundation
import XCTest

@testable import WakeGuard

/// WG-304: the travel-update notification. Pins the pure decision (notify only when a zone-change
/// reconcile actually shifted an alarm) and the coordinator wiring (reconcile → notify-if-changed → carry
/// the new zone). The real UNUserNotifications post is device-only; the coordinator is tested with a fake
/// notifier. It never affects an alarm — a missed notification is safe (#9).
final class TravelUpdateNotificationTests: XCTestCase {

    // MARK: pure policy

    func testNotifyOnlyWhenReconcileMovedAnAlarm() {
        var scheduled = ReconciliationSummary()
        scheduled.scheduled = 1
        XCTAssertTrue(TravelNotificationPolicy.shouldNotify(summary: scheduled))

        var cancelled = ReconciliationSummary()
        cancelled.cancelled = 2
        XCTAssertTrue(TravelNotificationPolicy.shouldNotify(summary: cancelled))

        // Nothing moved (all "stay fixed", or no alarms) → no notification.
        XCTAssertFalse(TravelNotificationPolicy.shouldNotify(summary: ReconciliationSummary()))

        // A skipped reconcile (system authority unreadable) → no notification, even if counts look set.
        var skipped = ReconciliationSummary()
        skipped.skipped = true
        skipped.scheduled = 1
        XCTAssertFalse(TravelNotificationPolicy.shouldNotify(summary: skipped))
    }

    // MARK: coordinator wiring

    @MainActor
    func testCoordinatorNotifiesWithTheNewZoneWhenAlarmsShifted() async throws {
        let processor = FakeAlarmCommandProcessor()
        var summary = ReconciliationSummary()
        summary.scheduled = 1
        processor.setReconcileSummary(summary)
        let notifier = SpyTravelNotifier()
        let coordinator = TravelUpdateCoordinator(processor: processor, notifier: notifier)

        await coordinator.handleZoneChange(
            TimeZoneChange(
                previous: try IANATimeZone(identifier: "America/New_York"),
                current: try IANATimeZone(identifier: "Asia/Tokyo")))

        XCTAssertEqual(processor.reconcileCount, 1, "the zone change reconciles alarms")
        XCTAssertEqual(
            notifier.zones.map(\.identifier), ["Asia/Tokyo"],
            "notified once, carrying the new zone")
    }

    @MainActor
    func testCoordinatorDoesNotNotifyWhenNothingChanged() async throws {
        let processor = FakeAlarmCommandProcessor()  // default summary: all zeros
        let notifier = SpyTravelNotifier()
        let coordinator = TravelUpdateCoordinator(processor: processor, notifier: notifier)

        await coordinator.handleZoneChange(
            TimeZoneChange(
                previous: try IANATimeZone(identifier: "America/New_York"),
                current: try IANATimeZone(identifier: "America/Los_Angeles")))

        XCTAssertEqual(processor.reconcileCount, 1, "it still reconciles")
        XCTAssertTrue(notifier.zones.isEmpty, "but posts no notification when nothing moved")
    }
}

/// Records the zones a travel notification was posted for.
private final class SpyTravelNotifier: TravelUpdateNotifying, @unchecked Sendable {
    private let box = Synchronized<[IANATimeZone]>([])
    var zones: [IANATimeZone] { box.get() }
    func notifyAlarmsUpdated(forNewZone zone: IANATimeZone) async {
        box.mutate { $0.append(zone) }
    }
}
