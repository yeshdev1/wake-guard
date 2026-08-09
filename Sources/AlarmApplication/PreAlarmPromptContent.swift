import Foundation

/// A button the pre-alarm prompt presents (WG-083). Distinct from `PreAlarmAction` (the user's policy
/// set) because **`keep` is always present** — the safe default that #7 guarantees when the user
/// doesn't act — and each button carries the presentation metadata: a stable identifier (for routing
/// the tapped response), a localization key, and the notification semantics.
enum PreAlarmPromptAction: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case keep
    case turnOffToday
    case changeTime
    case remindLater

    /// Stable identifier for the notification action + response routing (never localized).
    var identifier: String { "prealarm.action.\(rawValue)" }
    /// Localization key for the button title — resolved at the notification boundary (E11 localizes).
    var titleKey: String { "prealarm.action.\(rawValue).title" }
    /// Whether the action changes or stops the alarm — maps to `UNNotificationAction`'s `.destructive`
    /// and is the set that needs confirmation on a critical alarm (#6). `keep` / `remindLater` are safe.
    var isDestructive: Bool { self == .turnOffToday || self == .changeTime }
    /// Whether choosing it must open the app (changing the time needs a picker).
    var opensApp: Bool { self == .changeTime }
}

/// One resolved button of the prompt (WG-083): its action + presentation flags.
struct PreAlarmPromptButton: Sendable, Equatable, Hashable {
    let action: PreAlarmPromptAction
    let titleKey: String
    let isDestructive: Bool
    /// A critical alarm's destructive action (#6). At the notification layer this maps only to a
    /// device-**unlock** gate (`.authenticationRequired`) — NOT the explicit "are you sure?"
    /// confirmation. The real confirmation + the mutation are the prompt runtime's job, routed through
    /// `AlarmCommandProcessor` (which returns `.needsConfirmation` for an unconfirmed critical change).
    /// Only ever `true` for a destructive button; `keep` / `remindLater` never confirm.
    let requiresConfirmation: Bool
    /// Whether the action opens the app.
    let opensApp: Bool
}

/// The pre-alarm prompt's presentation model (WG-083) — the ordered buttons + the title/warning keys.
/// Built from a WG-082 `PreAlarmRecommendation`; Foundation-only, so it holds no alarm authority and
/// changes nothing (a movement inference still never cancels, #8). The warning states the original
/// alarm remains unless the user amends it (#7). Localization-ready: every string is a key.
struct PreAlarmPromptContent: Sendable, Equatable {
    /// The notification category identifier iOS registers this prompt under.
    static let categoryIdentifier = "prealarm.prompt"
    static let titleKey = "prealarm.prompt.title"
    /// The #7 warning key — its copy states the original alarm stays scheduled unless amended.
    static let warningKey = "prealarm.prompt.warning"

    /// Presentation order: the safe default first, then least → most destructive, so a destructive
    /// turn-off is never the first button (and renders distinctly via `.destructive`).
    static let presentationOrder: [PreAlarmPromptAction] = [
        .keep, .remindLater, .changeTime, .turnOffToday,
    ]

    /// The ordered buttons — `keep` is always first.
    let buttons: [PreAlarmPromptButton]
    let titleKey: String
    let warningKey: String

    /// Build the prompt content for a recommendation, or `nil` when it does not recommend a prompt.
    /// `keep` is always included; the other buttons appear only as the user's policy configured them.
    static func from(_ recommendation: PreAlarmRecommendation) -> PreAlarmPromptContent? {
        guard recommendation.shouldPrompt else { return nil }
        let offered = recommendation.offeredActions
        let buttons = presentationOrder.compactMap { action -> PreAlarmPromptButton? in
            let isConfigured =
                action == .keep
                || PreAlarmAction(rawValue: action.rawValue).map(offered.contains) ?? false
            guard isConfigured else { return nil }
            return PreAlarmPromptButton(
                action: action, titleKey: action.titleKey, isDestructive: action.isDestructive,
                requiresConfirmation: recommendation.requiresConfirmation && action.isDestructive,
                opensApp: action.opensApp)
        }
        return PreAlarmPromptContent(buttons: buttons, titleKey: titleKey, warningKey: warningKey)
    }
}

/// Development-language (English) copy for the pre-alarm prompt (WG-083). Localization-ready: the
/// notification layer resolves each key via `NSLocalizedString`, falling back to these values; E11
/// supplies the translated `.strings`. Kept as data (not literals in the adapter) so the copy —
/// especially the #7 warning — is unit-testable.
enum PreAlarmPromptStrings {
    static let developmentValues: [String: String] = [
        PreAlarmPromptContent.titleKey: "You're up before your alarm",
        PreAlarmPromptContent.warningKey:
            "Your original alarm stays scheduled unless you change it.",
        PreAlarmPromptAction.keep.titleKey: "Keep alarm",
        PreAlarmPromptAction.turnOffToday.titleKey: "Turn off today",
        PreAlarmPromptAction.changeTime.titleKey: "Change time",
        PreAlarmPromptAction.remindLater.titleKey: "Remind later",
    ]

    /// The development-language **fallback** for a key — NOT a localizer. Display strings must be
    /// resolved through `NSLocalizedString(key, value:comment:)` at the notification boundary (see the
    /// category factory, which does this for action titles; the notification *body* — title/warning —
    /// is the prompt runtime's to resolve the same way). This is only the dev-English `value:` fallback
    /// and a test shim; named so a future body builder doesn't mistake it for localization.
    static func developmentFallback(for key: String) -> String { developmentValues[key] ?? key }
}
