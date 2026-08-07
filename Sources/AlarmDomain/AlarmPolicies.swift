import Foundation

/// User-assigned importance. A `.critical` alarm gets the protections of
/// SAFETY_INVARIANTS #6–#8; the policy engine — not this model, and never a
/// model provider — assigns it (#31). Operational defaults are ADR-007.
enum Criticality: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case standard
    case critical
}

/// Reference to the alarm's sound resource.
struct AlarmSound: Codable, Sendable, Equatable, Hashable {
    let identifier: String

    static let `default` = AlarmSound(identifier: "default")
}

/// Snooze deferral policy. A disabled policy is the canonical `.disabled`; an
/// enabled one is built through the validating `enabled(interval:maximumCount:)`
/// factory, so a positive interval and count are guaranteed. (For a critical
/// alarm, a snooze is a #6-gated delay — enforced by the policy engine, WG-028.)
struct SnoozePolicy: Codable, Sendable, Equatable, Hashable {
    let isEnabled: Bool
    let interval: TimeInterval
    let maximumCount: Int

    private init(isEnabled: Bool, interval: TimeInterval, maximumCount: Int) {
        self.isEnabled = isEnabled
        self.interval = interval
        self.maximumCount = maximumCount
    }

    static let disabled = SnoozePolicy(isEnabled: false, interval: 0, maximumCount: 0)

    static func enabled(interval: TimeInterval, maximumCount: Int) throws -> SnoozePolicy {
        guard interval > 0 else {
            throw DomainError.invalidSnoozePolicy(reason: "interval must be > 0")
        }
        guard maximumCount >= 1 else {
            throw DomainError.invalidSnoozePolicy(reason: "maximumCount must be >= 1")
        }
        return SnoozePolicy(isEnabled: true, interval: interval, maximumCount: maximumCount)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, interval, maximumCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(Bool.self, forKey: .isEnabled) {
            self = try SnoozePolicy.enabled(
                interval: container.decode(TimeInterval.self, forKey: .interval),
                maximumCount: container.decode(Int.self, forKey: .maximumCount))
        } else {
            self = .disabled
        }
    }
}

/// Pre-alarm movement-check policy. Disabled is canonical; enabled requires a
/// positive lead time. Evaluation-window defaults are ADR-008.
/// An action the smart pre-alarm prompt may offer (PRODUCT_SPEC §3.3). "Keep original alarm" is
/// always available implicitly — it is the no-op that #7 guarantees when the user doesn't respond
/// — so it is never in this set. This set is the user-controlled subset the prompt presents.
enum PreAlarmAction: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case turnOffToday
    case changeTime
    case remindLater
}

struct PreAlarmPolicy: Codable, Sendable, Equatable, Hashable {
    let isEnabled: Bool
    let leadTime: TimeInterval
    /// The actions the pre-alarm prompt offers (WG-047). Empty when disabled, and may be empty
    /// even when enabled (a purely informational prompt — the user still keeps the alarm by
    /// default, #7). Enforcement of the critical-alarm confirmation on these actions is the
    /// pre-alarm runtime's job; the policy engine already gates any resulting destructive command.
    let allowedActions: Set<PreAlarmAction>

    private init(isEnabled: Bool, leadTime: TimeInterval, allowedActions: Set<PreAlarmAction>) {
        self.isEnabled = isEnabled
        self.leadTime = leadTime
        self.allowedActions = allowedActions
    }

    static let disabled = PreAlarmPolicy(isEnabled: false, leadTime: 0, allowedActions: [])

    static func enabled(
        leadTime: TimeInterval, allowedActions: Set<PreAlarmAction> = []
    ) throws -> PreAlarmPolicy {
        guard leadTime > 0 else {
            throw DomainError.invalidPreAlarmPolicy(reason: "leadTime must be > 0")
        }
        return PreAlarmPolicy(isEnabled: true, leadTime: leadTime, allowedActions: allowedActions)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, leadTime, allowedActions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(Bool.self, forKey: .isEnabled) {
            let actions =
                try container.decodeIfPresent(Set<PreAlarmAction>.self, forKey: .allowedActions)
                ?? []
            self = try PreAlarmPolicy.enabled(
                leadTime: container.decode(TimeInterval.self, forKey: .leadTime),
                allowedActions: actions)
        } else {
            self = .disabled
        }
    }
}

/// What an alarm does when the device's time zone changes (SCOPE §2.4).
/// A location/region signal can never *silently* move a critical schedule
/// (SAFETY_INVARIANTS #16) — the region rule always carries an explicit safe
/// fallback, and confirmation is enforced by the policy engine.
enum TravelBehavior: Codable, Sendable, Equatable, Hashable {
    case followLocal
    case stayFixed
    case askOnChange
    case regionRule(RegionRule)
}

/// An optional region-based enable/disable rule with a mandatory, non-region
/// safe fallback.
struct RegionRule: Codable, Sendable, Equatable, Hashable {
    let regionIdentifier: String
    let safeFallback: SafeFallback
}

/// The safe fallback for a region rule — deliberately not itself a region rule,
/// so there is always a concrete, non-recursive behavior.
enum SafeFallback: String, Codable, Sendable, Equatable, Hashable {
    case followLocal
    case stayFixed
}
