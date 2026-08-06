import Foundation

/// The MVP travel-behavior options for the alarm form (WG-046) — the three simple choices the
/// UI exposes, mapped to the domain `TravelBehavior`. `.regionRule` (WG-021) is not
/// user-creatable in the MVP; a seeded region rule maps to `.ask`, preserving its rule-based,
/// never-silently-shift spirit (#16). None of these options shift a schedule *silently*:
/// follow-local and keep-zone are explicit fixed policies, and ask prompts before moving.
enum TravelOption: Sendable, CaseIterable, Hashable {
    case followLocal
    case keepZone  // TravelBehavior.stayFixed
    case ask  // TravelBehavior.askOnChange

    init(from behavior: TravelBehavior) {
        switch behavior {
        case .followLocal: self = .followLocal
        case .stayFixed: self = .keepZone
        case .askOnChange, .regionRule: self = .ask
        }
    }

    var behavior: TravelBehavior {
        switch self {
        case .followLocal: .followLocal
        case .keepZone: .stayFixed
        case .ask: .askOnChange
        }
    }

    var title: String {
        switch self {
        case .followLocal: "Follow local time"
        case .keepZone: "Keep home-zone time"
        case .ask: "Ask when I travel"
        }
    }

    /// Plain-language preview of what happens at a destination in another time zone. `timeText`
    /// is the alarm's wall-clock time; `zone` is the human-readable anchor zone. The copy never
    /// implies location tracking — a *time-zone change* is the trigger, not continuous GPS — and
    /// the `.ask` behavior is stated as the alarm's policy (the travel detection itself is E06),
    /// not as something the app does today.
    func destinationDescription(timeText: String, zone: String) -> String {
        switch self {
        case .followLocal:
            return "Rings at \(timeText) in whatever time zone your device is in — it follows "
                + "local time."
        case .keepZone:
            return "Always rings at \(timeText) \(zone) time, even when you travel."
        case .ask:
            return "Keeps \(zone) time, and will ask before shifting if your time zone changes — "
                + "it never moves the alarm on its own."
        }
    }
}
