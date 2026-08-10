import Foundation

/// How certain a device time-zone change reflects **real travel** (WG-101). A zone change alone is
/// inherently ambiguous — a VPN, a manual clock change, or a genuine trip all move the system zone — so
/// the confirmed zone (a fact) is kept separate from location corroboration (an optional, stronger
/// signal). VPN / network state is **never** treated as location, so it can never raise this above
/// `zoneChangeOnly`.
enum TravelCertainty: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// A confirmed time-zone change with no corroboration — it could be a VPN or a manual change, so a
    /// travel action must treat it cautiously (WG-104).
    case zoneChangeOnly
    /// A time-zone change **corroborated by a significant-location change** — likely real travel.
    case corroboratedByLocation
}

/// Optional, coarse location corroboration for a travel inference (WG-101). Deliberately **coarse** and
/// sourced from **significant-location only** (WG-102), never continuous GPS or a network/VPN signal
/// (#41 privacy). It stores **no coordinates** — only *whether* the device meaningfully moved — so it
/// reveals nothing about where the user is. Absent from a `TravelContext` when location is
/// unavailable/denied.
struct LocationContext: Sendable, Equatable, Hashable, Codable {
    /// Whether a significant-location change accompanied the zone change (the corroboration). Coarse: a
    /// bool, no coordinates (#41).
    let significantLocationChanged: Bool
    /// When this location context was observed.
    let observedAt: Date
}

/// The travel context (WG-101): the **confirmed** system time-zone change (always present) plus
/// **optional** coarse location corroboration, with an explicit certainty and timestamps. A later task
/// (WG-104) turns this into a policy decision; the context itself holds **no alarm authority** and
/// re-anchors nothing (#8/#11).
struct TravelContext: Sendable, Equatable, Hashable, Codable {
    /// The confirmed device zone change — always present (from the system time zone, WG-100).
    let zoneChange: TimeZoneChange
    /// When the zone change was detected.
    let detectedAt: Date
    /// Optional coarse location corroboration — `nil` when there is no genuine location signal (denied /
    /// unavailable). A VPN/network-induced zone change leaves this `nil`, so it stays `.zoneChangeOnly`.
    let location: LocationContext?

    /// The certainty this reflects real travel. Only a **genuine** significant-location change raises it;
    /// a zone change alone — or location that reports no movement — is `.zoneChangeOnly` (ambiguous).
    var certainty: TravelCertainty {
        if let location, location.significantLocationChanged {
            return .corroboratedByLocation
        }
        return .zoneChangeOnly
    }
}
