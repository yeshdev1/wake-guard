import Foundation

extension AppEnvironment {
    /// The device time-zone monitor whose `onChange` reconciles alarms in the new zone (WG-100). The
    /// persisted state store is a `UserDefaultsTimeZoneStateStore`; only `RootView` (production) starts it,
    /// so the in-memory graph composes it but never touches UserDefaults / `NotificationCenter` /
    /// `TimeZone.current`. Kept in its own file so `AppEnvironment.swift` — which also names the cloud
    /// token — never mentions UserDefaults (the secret-handling audit's proximity guard).
    static func makeTimeZoneMonitor(
        processor: any AlarmCommandProcessing
    ) -> SystemTimeZoneMonitor {
        SystemTimeZoneMonitor(
            store: UserDefaultsTimeZoneStateStore(),
            onChange: { _ in Task { _ = await processor.reconcile() } })
    }
}
