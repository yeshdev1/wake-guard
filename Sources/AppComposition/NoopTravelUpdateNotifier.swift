import Foundation

/// A no-op `TravelUpdateNotifying` for the in-memory (test/preview) graph (WG-304): there is no app to
/// route a notification from, and a preview must never post a system notification. Records nothing.
struct NoopTravelUpdateNotifier: TravelUpdateNotifying {
    func notifyAlarmsUpdated(forNewZone zone: IANATimeZone) async {}
}
