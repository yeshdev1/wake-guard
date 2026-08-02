import Foundation

/// An IANA time-zone identifier (e.g. `America/New_York`). Enforces
/// SAFETY_INVARIANTS #11: only geographic tz-database identifiers are accepted —
/// the fixed-offset `GMT`/`GMT±HHMM` family is rejected, so a stored alarm can
/// never carry an offset-only zone. (`UTC` and the named `Etc/*` zones are kept.)
struct IANATimeZone: Codable, Sendable, Equatable, Hashable {
    let identifier: String

    init(identifier: String) throws {
        // Reject the fixed-offset GMT family up front: "GMT", "GMT+0", "GMT-0",
        // "GMT+0530", etc. all denote an offset with no geographic/DST identity
        // (#11). `UTC` and `Etc/*` do not start with "GMT" and are kept.
        guard !identifier.hasPrefix("GMT") else {
            throw DomainError.timeZoneNotIANA(identifier)
        }
        // `knownTimeZoneIdentifiers` has alias gaps (e.g. lists Asia/Calcutta but
        // not Asia/Kolkata, and omits UTC), so validate by resolution, and also
        // reject inputs that canonicalize to a GMT±HHMM offset (e.g. "UTC+5").
        guard let resolved = TimeZone(identifier: identifier) else {
            throw DomainError.timeZoneNotIANA(identifier)
        }
        let canonical = resolved.identifier
        guard !canonical.hasPrefix("GMT+"), !canonical.hasPrefix("GMT-") else {
            throw DomainError.timeZoneNotIANA(identifier)
        }
        self.identifier = identifier
    }

    init(_ timeZone: TimeZone) throws {
        try self.init(identifier: timeZone.identifier)
    }

    /// The Foundation `TimeZone`. The identifier is validated on construction, so
    /// the fallback is never taken; it only keeps this free of force-unwraps.
    var timeZone: TimeZone {
        TimeZone(identifier: identifier) ?? .gmt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(identifier: container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }
}
