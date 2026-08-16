import Foundation

extension AppEnvironment {
    /// The device time-zone monitor whose `onChange` reconciles alarms in the new zone (WG-100). The
    /// persisted state store is a `UserDefaultsTimeZoneStateStore`; only `RootView` (production) starts it,
    /// so the in-memory graph composes it but never touches UserDefaults / `NotificationCenter` /
    /// `TimeZone.current`. Kept in its own file so `AppEnvironment.swift` — which also names the cloud
    /// token — never mentions UserDefaults (the secret-handling audit's proximity guard).
    static func makeTimeZoneMonitor(
        processor: any AlarmCommandProcessing, notifier: any TravelUpdateNotifying
    ) -> SystemTimeZoneMonitor {
        // A detected zone change reconciles alarms into the new zone, then posts an FYI **only** if that
        // actually shifted an alarm (WG-304). The coordinator holds that decision so it's unit-tested.
        let coordinator = TravelUpdateCoordinator(processor: processor, notifier: notifier)
        return SystemTimeZoneMonitor(
            store: UserDefaultsTimeZoneStateStore(),
            onChange: { change in Task { await coordinator.handleZoneChange(change) } })
    }
}
