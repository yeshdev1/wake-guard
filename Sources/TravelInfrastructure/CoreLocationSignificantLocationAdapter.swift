import CoreLocation
import Foundation
import Synchronization

/// The real low-power significant-location source (WG-102). It uses **only**
/// `startMonitoringSignificantLocationChanges` — cell / Wi-Fi based, **never continuous GPS**
/// (`startUpdatingLocation` is never called) — so it is battery-frugal and reveals only coarse
/// movement. It records **only the timestamp** of a *fresh* significant change (never coordinates, #41),
/// rejecting the **cached** location Core Location delivers first via `SignificantLocationFilter`. When
/// authorization is denied / restricted it monitors nothing and reports no change, so time-zone travel
/// detection (WG-100) is unaffected.
///
/// Not unit-tested — `CLLocationManager` needs a device; the pure freshness filter is tested in
/// `TravelDomain`. `@unchecked Sendable`: the only mutable state is a `Mutex`-guarded timestamp; the
/// injected clock is immutable, and `CLLocationManager` is confined to the thread that created it.
final class CoreLocationSignificantLocationAdapter: NSObject, SignificantLocationSource,
    CLLocationManagerDelegate, @unchecked Sendable
{
    private let manager = CLLocationManager()
    private let lastChange = Mutex<Date?>(nil)
    private let now: @Sendable () -> Date
    private let maxAge: TimeInterval

    init(
        now: @escaping @Sendable () -> Date,
        maxAge: TimeInterval = SignificantLocationFilter.defaultMaxAge
    ) {
        self.now = now
        self.maxAge = maxAge
        super.init()
        manager.delegate = self
    }

    func authorizationStatus() async -> LocationAuthorizationStatus {
        Self.map(manager.authorizationStatus)
    }

    func lastSignificantChange() async -> Date? {
        lastChange.withLock { $0 }
    }

    /// Request when-in-use authorization and begin low-power significant-location monitoring. Idempotent;
    /// a denial simply yields no changes (travel detection falls back to the time-zone observer).
    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startMonitoringSignificantLocationChanges()
    }

    func stop() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Reject the cached/stale sample Core Location delivers first — only a fresh change counts — and
        // keep ONLY its timestamp, never the coordinates (#41).
        guard SignificantLocationFilter.isFresh(location.timestamp, now: now(), maxAge: maxAge)
        else {
            return
        }
        lastChange.withLock { $0 = location.timestamp }
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedAlways: .authorizedAlways
        case .authorizedWhenInUse: .authorizedWhenInUse
        @unknown default: .denied  // fail closed — never assume authorized
        }
    }
}
